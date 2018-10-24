#!/usr/bin/perl
#
# rsync-backup
# Copyright 2018 by Jay Osborne
# Licensed GPL 3.0
#
# This program syncs a NFS folder to another folder
#
#
#
# Run ---> perltidy -bli -ibc -l=200 new-backup-perl.pl to clean up formatting
#
#
# IMPORTANT NOTE: You must install EMAIL::MIME Perl module
#
# For Ubuntu run:  apt-get install libemail-mime-perl, libemail-sender-perl
#
#

use strict;
use warnings;
use Sys::Syslog;                          # Required module for writing to syslog
use Sys::Syslog qw(:standard :macros);    # standard functions & macros
use Email::MIME;                          # Required module for sending email from Perl -- SEE NOTES ABOVE
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP ();
use Email::Simple                  ();
use Email::Simple::Creator         ();
use Try::Tiny;                            # Required module for exception handling commands try and catch

#
# Constants
#
my $FALSE = 0;
my $TRUE  = 1;

#
# Variable Initializations
#
#
my $email_recipient = 'logwatchers@example.com';       # Use single quote to prevent Perl interpreting the at symbol in email address
my $email_sender    = 'backup-script@example.com';     # Use single quote to prevent Perl interpreting the at symbol in email address
my $email_subject   = "Backup-Script FAILURE ERROR";
my $smtp_host       = "mail.example.com";

my $VarMountCmd    = "/bin/mount -o ro -t nfs";
my $VarUmountCmd   = "/bin/umount";
my $VarChkMountCmd = '/bin/mount | /bin/grep';
my $VarSyncCmd     = "/usr/bin/rsync -va --delete";    #  Very damgerous unless you are sure all bugs are squashed.  Otherwise use -van

#
#  *************************** BEGIN  Subroutines  ***************************
#
#  This is the beginning of the subroutine definitions...
#
#

#
# This subroutine gets the local time and returns a standard timestamp string to the calling
# routine
#

sub get_the_timestamp
  {
    my $VarName;
    my $VarTimeStamp;
    my $VarZero;
    my ( $VarSec, $VarMin, $VarHour, $VarMday, $VarMon, $VarYear, $VarWday, $VarYday, $VarIsdst ) = localtime();    # Standard textbook call to localtime
    $VarYear = $VarYear + 1900;                                                                                     # $VarYear is number of years since 1900
    if    ( $VarMon == 0 )  { $VarName = "Jan"; }                                                                   # Convert month number {0-9} to a three letter name
    elsif ( $VarMon == 1 )  { $VarName = "Feb"; }                                                                   # Case/Switch does not work in Perl
    elsif ( $VarMon == 2 )  { $VarName = "Mar"; }                                                                   # Old school if/elsif has to be used
    elsif ( $VarMon == 3 )  { $VarName = "Apr"; }
    elsif ( $VarMon == 4 )  { $VarName = "May"; }
    elsif ( $VarMon == 5 )  { $VarName = "Jun"; }
    elsif ( $VarMon == 6 )  { $VarName = "Jul"; }
    elsif ( $VarMon == 7 )  { $VarName = "Aug"; }
    elsif ( $VarMon == 8 )  { $VarName = "Sep"; }
    elsif ( $VarMon == 9 )  { $VarName = "Oct"; }
    elsif ( $VarMon == 10 ) { $VarName = "Nov"; }
    elsif ( $VarMon == 11 ) { $VarName = "Dec"; }
    else                    { $VarName = "XXX"; }

    if ( $VarSec < 10 )
      {
        $VarZero = "$VarSec";            # To add a leading zero for 0-9 you need to convert to string first
        $VarSec  = ( "0" . $VarZero );
      }                                  # Then concatenate with a zero
    if ( $VarMin < 10 )
      {
        $VarZero = "$VarMin";            # To add a leading zero for 0-9 you need to convert to string first
        $VarMin  = ( "0" . $VarZero );
      }                                  # Then concatenate with a zero
    if ( $VarHour < 10 )
      {
        $VarZero = "$VarHour";           # To add a leading zero for 0-9 you need to convert to string first
        $VarHour = ( "0" . $VarZero );
      }                                  # Then concatenate with a zero
    if ( $VarMday < 10 )
      {
        $VarZero = "$VarMday";           # To add a leading zero for 0-9 you need to convert to string first
        $VarMday = ( "0" . $VarZero );
      }                                  # Then concatenate with a zero
    $VarTimeStamp = "$VarName $VarMday $VarYear $VarHour:$VarMin:$VarSec";
    return ($VarTimeStamp);
  }

#
# This subroutine verifies that the user is root.  Otherwise mount cannot be called
# and the whole thing is doomed
#
# Do not send error email or log to syslog.
#
sub check_your_privilege
  {
    if ( $> != 0 )    # $> translates to $EFFECTIVE_USER_ID in "use Englsh" module;
      {
        notify_error("rsync-backup must be invoked with root privilege to run mount\n");
        return (7);
      }
    return (0);
  }

#
# This subroutine sends an email message argument to the email user listed in the global variables
#
#
sub send_error_email
  {
    ( my $VarErrorMsg ) = $_[0];         # Load the error message string from the ARGs array
                                         #
                                         # First we build the message object
                                         #
    my $message = Email::MIME->create    # Build the mail message object
      (
        header_str => [
            From    => $email_sender,
            To      => $email_recipient,
            Subject => $email_subject,
        ],
        attributes => {
            encoding => 'quoted-printable',
            charset  => 'ISO-8859-1',
        },
        body_str => "$VarErrorMsg\n",
      );

    my $transport = Email::Sender::Transport::SMTP->new(
        {                                # Create a transport object otherwise Perl tries to use localhost
            host => $smtp_host,          # Force Perl to send directly to the mail server port 25
            port => 25,
        }
    );
    #
    # Now we send the message
    #
    # If sending mail fails we do not want to crash the program so we use try and catch.
    # The sendmail command will kill perl and exit badly if it fails.  Try and catch will
    # make an attempt and if it fails will run the exception in catch without causing the
    # script to die.
    try
    {
        sendmail( $message, { transport => $transport } );
    }
    catch
    {
        log_error("Failed to send email warning to System Admin");
        notify_error("Failed to send email warning to System Admin");
        return (8)
    };    # <--- This trailing semicolon MUST BE PRESENT!!!!!!  MUY IMPORTANTE!!!!  The whole try/catch block will skip otherwise.
    return (0);
  }

#
# This subroutine sends the passed error message to the syslog.  If the routine
# gets called without a single parameter a generic message is called.
#
sub log_error
  {
    my $VarLogMessage;
    my $num_args     = @_;                    # Find the number of variables from the ARGs array
    my $VarTimeStamp = get_the_timestamp();
    if ( $num_args != 1 )                     # If we have more (or less) than one argument we display a generic message to the log.
      {
        $VarLogMessage = "BackupScript Failure: -> Unidentified Failure Error in backup script";
      }
    else
      {
        ( my $VarErrorMsg ) = $_[0];          # Load the variables from the ARGs array
        $VarLogMessage = "BackupScript Failure: -> $VarErrorMsg";
      }
    openlog( 'rsync-backup-script', 'cons,pid', 'user' );    # Log has to be opened before writing
    syslog( 'ERR', '%s', $VarLogMessage );                   # Sending message with priority ERROR to make sure it makes it to greylog server
    closelog();
  }

#
# This subroutine prints out the passed error message.  If the routine
# gets called without a single parameter a generic message is called.
#
# Use for testing to prevent too many log entries and emails...
#
sub notify_error
  {
    my $num_args     = @_;                    # Find the number of variables from the ARGs array
    my $VarTimeStamp = get_the_timestamp();
    my $VarErrorMsg;
    if ( $num_args != 1 )
      {
        $VarErrorMsg = "Unidentified Failure Error in backup script";
      }
    else
      {
        ($VarErrorMsg) = $_[0];               # Load the variables from the ARGs array
      }
    print "$VarTimeStamp BackupScript Failure: -> $VarErrorMsg\n";
  }

#
# This subroutine prints out the passed message.  If the routine
# gets called without a single parameter a generic message is called.
#
# Use for testing to prevent too many log entries and emails...
#
sub notify_info
  {
    my $num_args     = @_;                    # Find the number of variables from the ARGs array
    my $VarTimeStamp = get_the_timestamp();
    my $VarErrorMsg;
    if ( $num_args != 1 )
      {
        $VarErrorMsg = "General Notification -- Something happened";
      }
    else
      {
        ($VarErrorMsg) = $_[0];               # Load the variables from the ARGs array
      }
    print "$VarTimeStamp BackupScript Notice: -> $VarErrorMsg\n";
  }

#
# This subroutine sends out the passed error message by email and places a copy in the syslog.  If the routine
# gets called without a single parameter a generic message is called.
#
sub full_error_notification
  {
    my $num_args = @_;                   # Find the number of variables from the ARGs array
    my $VarErrorMsg;
    if ( $num_args != 1 )
      {
        $VarErrorMsg = "Unidentified Failure Error in backup script";
      }
    else
      {
        ($VarErrorMsg) = $_[0];          # Load the variables from the ARGs array
      }
    notify_error("$VarErrorMsg");
    log_error($VarErrorMsg);
    send_error_email($VarErrorMsg);
  }

#
# This subroutine attempts to mount an NFS share.  If is fails for any reason
# it sends a failure message and returns an error code.
#
# /bin/mount -t nfs -o ro <source NFS share> <destination mountpoint>
sub mount_readonly
  {
    my $VarProgramResult;
    my $num_args = @_;                   # Find the number of variables from the ARGs array
    if ( $num_args != 2 )                # There better be only two arguments to the mount command
      {
        notify_error("NFS Mount failure.  Incorrect number of parameters passed to mount command");
        return (1);
      }
    ( my $VarSourceDir, my $VarMountPoint ) = @_;    # Load the variables from the ARGs array
    if ( -e $VarMountPoint and -d $VarMountPoint )   # Check to see if the mountpoint exists and is a directory
      {
        notify_info("Attempting to mount NFS share <$VarSourceDir> at mountpoint <$VarMountPoint>");
      }
    else
      {
        notify_error("Mount failure.  Destination mountpoint: <$VarMountPoint> does not exist or cannot be mounted");
        return (2);
      }
    my $VarMounted = `$VarChkMountCmd $VarMountPoint`;    # Check to see if the destination directory is already mounted with something
    if ($VarMounted)
      {
        notify_error("Mount failure.  Destination mountpoint: <$VarMountPoint> is already mounted");    # Don't mount if it's occupied
        return (20);
      }
    $VarProgramResult = `$VarMountCmd $VarSourceDir $VarMountPoint`;                                    # Run the mount command externally
    if ($?)                                                                                             #  $? is the numeric return code returned from the external program
      {
        notify_error("Mount failure.  Failed to mount NFS share <$VarSourceDir> at mountpoint <$VarMountPoint> with error $?");
        return (3);
      }
    notify_info("NFS share <$VarSourceDir> successfully mounted at mountpoint <$VarMountPoint>");
    return (0);
  }

#
# This subroutine attempts to mount an NFS share.  If is fails for any reason
# it sends a failure message and returns an error code.
#
# /bin/mount -t nfs -o ro <source NFS share> <destination mountpoint>
sub unmount_share
  {
    my $VarProgramResult;
    my $num_args = @_;                   # Find the number of variables from the ARGs array
    if ( $num_args != 1 )
      {
        notify_error("NFS Mount failure.  Incorrect number of parameters passed to umount command.");
        return (4);
      }
    ( my $VarMountPoint ) = $_[0];       # Load the variable from the ARGs array

    #    notify_info ( "Unmounting NFS share from mountpoint <$VarMountPoint>" );
    if ( -e $VarMountPoint and -d $VarMountPoint )    # Check to see if the mountpoint exists and is a directory
      {
        notify_info("Calling umount to remove mountpoint <$VarMountPoint>");
      }
    else
      {
        notify_error("Mount failure.  Destination mountpoint: <$VarMountPoint> does not exist or cannot be unmounted");
        return (5);
      }
    $VarProgramResult = `$VarUmountCmd $VarMountPoint`;
    if ($?)                                           #  $? is the numeric return code returned from the external program
      {
        notify_error("Mount failure.  Destination mountpoint: <$VarMountPoint> failed to unmount with error $?");
        return (6);
      }
    notify_info("Mountpoint <$VarMountPoint> successfully removed with code $?");
    return (0);
  }

#
# This subroutine calls the mount function to set up the whole shebang.
# Then it copies the data from source to destination.  Afterwards, it
# unmounts the source directory.
#
# Do not send error email or log to syslog.
#
sub copy_the_data
  {
    my $VarProgramResult;
    my $num_args = @_;    # Find the number of variables from the ARGs array
    if ( $num_args != 3 )
      {
        notify_error("CopyData calling failure.  Incorrect number of parameters passed");
        return (10);
      }
    ( my $VarSourceDir, my $VarMountPoint, my $VarDestDir ) = @_;    # Load the variables from the ARGs array
    if ( !( -e $VarDestDir and -d $VarDestDir ) )                    # Check to see if the destination exists and is a directory
      {
        notify_info("Invalid destination directory <$VarDestDir>");
        return (11);
      }
    notify_info("Copying data from NFS share <$VarSourceDir> to destination <$VarDestDir> using temporary mountpoint <$VarMountPoint>");
    $VarProgramResult = mount_readonly( $VarSourceDir, $VarMountPoint );
    if ($VarProgramResult)
      {
        return (12);
      }
    my $VarTrailing = substr( $VarMountPoint, length($VarMountPoint) - 1, 1 );
    if ( $VarTrailing ne '/' )                                       # Check for a trailing slash in the mountpoint directory
      {                                                              # If none is provided we add one.  This prevents rsync
        notify_info("Correcting path name to prevent rsync from adding superfluous directory level");
        $VarMountPoint = $VarMountPoint . '/';                       # from creating a folder at the destionation same name
      }    # as the source folder directory
    notify_info("Copying data with rsync from <$VarMountPoint> to <$VarDestDir>.  Please wait...");
    my $VarCommandLine = $VarSyncCmd . ' ' . $VarMountPoint . ' ' . $VarDestDir;
    system($VarCommandLine );

    #    $VarProgramResult = `$VarSyncCmd $VarMountPoint $VarDestDir`;
    if ($?)    #  $? is the numeric return code returned from the external program
      {
        notify_error("Copy failure.  rsync failed with error $?");

        #        return (13);
      }
    else
      {
        notify_info("Rsync completed successfully with code $?");
      }
    $VarProgramResult = unmount_share($VarMountPoint);
    if ($VarProgramResult)
      {
        notify_error("BackupScript cannot continue.  You must manually unmount the NFS share");
        exit(120);    # If we get this far and couldn't unmount the NFS share, it's time to quit.  We don't want to mount again over it.
      }
    return (0);
  }

#
#
#
#  ******************************  BEGIN   ********************************
#
#  This is the beginning of the actual program execution...
#
#

print("\n\n");
notify_info("Start\n------------------Beginning BackupScript------------------\n");

#  if (check_your_privilege) {exit (100)}   # This short circuits the whole script if you fail to start as root

copy_the_data( "source", "destination", "mountpoint" );

notify_info("Completed Run\n\n-----------------------------------------------------------");
print "\n\n";

