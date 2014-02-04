#!/usr/bin/perl -l

# shuffledir.pl, Soren 2006-14
# Copy files from src dirs into dst dir.
# Shuffle the order, weighted by age, most recent first.

use strict;
use warnings;
use File::Copy;
use File::Find;
use File::Spec;
use Getopt::Long;

# Global variables
#
our(@srcdir ,$dstdir ,$df ,@oldfiles ,@newfiles, $writecounter);

# Command line paramenters
#
our(
  $verbose,
  $dirsize, $filesize, $margin, $ext, %ext,
  $copy, $symlink, $hardlink, $fillup,
);

# Convert a number with unit to integer
# Example: 8k -> 8192
#
sub eatunits {
  my $num = shift;

  return 1024**1 * substr $num, 0, -1 if substr($num, -1, 1) =~ /k/i;
  return 1024**2 * substr $num, 0, -1 if substr($num, -1, 1) =~ /m/i;
  return 1024**3 * substr $num, 0, -1 if substr($num, -1, 1) =~ /g/i;
  return $num;
}

# Find all files in source dir
#
sub scansrcdir {
  find(\&srcwanted, @_);
  our %srcfiles;
  sub srcwanted {
    return if -d;
    return if $File::Find::name =~ /\/\./; # Skip dot files/dirs

    # Only keep if extension matches
    if ( %ext ) {
      ( my $thisext = $File::Find::name ) =~ s/.*\.//;
      unless ( $ext{$thisext} ) {
        print "Ignore $File::Find::name (extention)" if $verbose;
        return;
      }
    }

    # Only keep files smaller than max file size
    my $size = -s;
    #print "Size of $File::Find::name is $size vs $filesize";
    #die;
    if ( $filesize and $size > $filesize ) {
      #print "Max $size > $filesize\n";
      print "Ignore $File::Find::name (filesize)" if $verbose;
      #die;
      return;
    }

    # Keep file
    $srcfiles{$File::Find::name}{name} = $File::Find::name;
    $srcfiles{$File::Find::name}{size} = -s;
    $srcfiles{$File::Find::name}{time} = -M;
  }
  printf("Found %s new files\n", scalar keys %srcfiles) if $verbose;
  return shuffle(\%srcfiles);
}

# Find all files in target dir
#
sub scandstdir {
  find(\&dstwanted, @_);
  our %dstfiles;
  sub dstwanted {
    return if -d;
    #my $filelist = shift;
    #return unless /\.(ogg|mp3)$/i;
    $dstfiles{$File::Find::name}{name} = $File::Find::name;
    $dstfiles{$File::Find::name}{size} = -s;
    $dstfiles{$File::Find::name}{time} = -M;
  }
  printf("Found %s old files\n", scalar keys %dstfiles) if $verbose;
  return reverse shuffle(\%dstfiles);
}

sub diskfree {
  if ( $dirsize) {
    $df = $dirsize - 1024 * `du -sk "$dstdir" | awk '{ print \$1}'`;
  } else {
    $df = 1024 * `df -k "$dstdir" | tail -1 | awk '{ print \$4 }'`;
  }
}

# Do a weighted shuffle of files depending on age of file
#
sub shuffle {
  my $href = shift;
  map { $$href{ $_->[0] } }
  sort { $a->[1] <=> $b->[1] }
  map { [ $_, rand() * ($$href{$_}{time}||1) ] }
  keys %$href;
}

sub nextfile { my $list=shift; return shift @$list }

sub delfile {
  my($file) = @_;

  return if $fillup;
  my $r = scalar @oldfiles;
  print "\[$r\] Delete $file" if $verbose;
  my $cnt = unlink "$file";
  print "    Warn: Could not delete" unless $cnt >= 1;
  diskfree();
}

sub copyfile {
  my $file = shift;
  return unless $file->{name} and -r $file->{name};
  if ( $file->{size} + $margin < $df ) {
    my $r = scalar @newfiles;
    my($v,$d,$f) = File::Spec->splitpath( $file->{name} );
    #my $dst = sprintf "%s/%03s_%s", $dstdir, ++$writecounter, $f;
    my $dst = sprintf "%s/%s", $dstdir, $f;
    #delbeforecopy( $file->{name} );

    # If file is already there, then don't need to copy.
    # Just remove file from todelete queue.
    for my $i ( 0 .. $#oldfiles ) {
      if ( $oldfiles[$i]{name} =~ /\/$f$/ ) {
        my $s = scalar @oldfiles;
        printf "\[$s\] Skip %s since already in dst folder\n", $f if $verbose;
        splice @oldfiles, $i, 1;
        return;
      }
    }
 
    #makespace($file) unless $fillup;
    #return unless $file->{size} + $margin < $df;
    print "\[$r\] Copy $file->{name} $dst" if $verbose;
    if ( $copy ) { 
      #copy($file->{name}, $dst);
      #sleep 2;
      system('rsync', '-P', $file->{name}, $dst);
    } elsif ( $symlink ) {
      symlink $file->{name}, $dst;
    } elsif ( $hardlink ) {
      link $file->{name}, $dst;
    }
    diskfree();
  }
}

sub makespace {
  my($file) = @_;
  my $size = $file->{size};
  while ( @oldfiles and $size+$margin > $df ) {
    my $del = nextfile(\@oldfiles);
    delfile($del->{name});
    my $need = $size+$margin;
    #print "Need $need has $df";
  }
}

sub initialstate {
  print "Scanning srcdirs @srcdir\n" if $verbose;
  @newfiles = scansrcdir(@srcdir);
  die "Error: No source files found\n" unless @newfiles;
  print "Scanning dstdir $dstdir\n" if $verbose;
  @oldfiles = scandstdir($dstdir);
  diskfree();
}

GetOptions(
  "margin=s"   => \$margin,    # Amount of free disk space
  "dirsize=s"  => \$dirsize,   # Max space used in target dir
  "filesize=s" => \$filesize,  # Max size of file
  "verbose"    => \$verbose,   # Write what is going on
  "copy"       => \$copy,      # Copy source files
  "symlink"    => \$symlink,   # Softlink to source files
  "hardlink"   => \$hardlink,  # Hardlink to source files
  "fillup"     => \$fillup,    # Keep existing files
  "ext=s"      => \$ext,       # Only kopy files with certain extensions
);

# Can specify many source dirs. Last dir specified is target dir.
@srcdir = @ARGV;
$dstdir = pop @srcdir;

# Convert units
$margin ||= '0m';
$margin   = eatunits($margin)   if $margin;
$dirsize  = eatunits($dirsize)  if $dirsize;
$filesize = eatunits($filesize) if $filesize;

# Extensions are comma seperated. Convert to hash keys
do { $ext{$_}++ for split /,/, $ext } if $ext;

initialstate();
# Copy new files
while ( my $file = nextfile(\@newfiles) ) {
  makespace($file) unless $fillup;
  copyfile($file);
}
# Delete all old ones
#print "Deleting remaining old ones";
while ( my $file = nextfile(\@oldfiles) ) {
  delfile($file->{name});
}

