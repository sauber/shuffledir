#!/usr/bin/perl -l

# shuffledir.pl, Soren 2006-08
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
our(@srcdir,$dstdir,$df,@oldfiles,@newfiles);
our($verbose,$margin,$copy,$symlink,$hardlink,$ext,%ext);
my $writecounter;

sub scansrcdir {
  find(\&srcwanted, @_);
  our %srcfiles;
  sub srcwanted {
    return if -d;
    return if $File::Find::name =~ /\/\./; # Skip dot files/dirs
    if ( %ext ) {
      ( my $thisext = $File::Find::name ) =~ s/.*\.//;
      unless ( $ext{$thisext} ) {
        print "Ignore $File::Find::name\n" if $verbose;
        return;
      }
    }
    #my $filelist = shift;
    #print "Read $_\n"; # XXX: debug
    #return unless /\.(ogg|mp3)$/i;
    #print "Keep $_\n"; # XXX: debug
    #return if $File::Find::name =~ /pimsleur/i;
    $srcfiles{$File::Find::name}{name} = $File::Find::name;
    $srcfiles{$File::Find::name}{size} = -s;
    $srcfiles{$File::Find::name}{time} = -M;
  }
  return shuffle(\%srcfiles);
}

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
  return reverse shuffle(\%dstfiles);
}

sub diskfree {
  $df = 1024 * `df -k "$dstdir" | tail -1 | awk '{ print \$4 }'`;
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

sub delbeforecopy {
  my($file) = @_;
  $file =~ s#^.*/##;
  my @todelete;
  my @tosplice;
  for my $i ( 0 .. $#oldfiles ) {
    #print "Compare $oldfiles[$i]{name} $file";
    if ( substr($oldfiles[$i]{name},-length $file) eq $file ) {
      push @todelete, $oldfiles[$i]{name};
      push @tosplice, $i;
    }
  }
  splice @oldfiles, $_, 1 for @tosplice;
  for $file ( @todelete ) {
    delfile($file);
  }
}

sub delfile {
  my($file) = @_;
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
    my $dst = sprintf "%s/%03s_%s", $dstdir, ++$writecounter, $f;
    delbeforecopy( $file->{name} );
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

sub old_copy {
  my($src,$dst) = @_;
  open IN, $src;
    open OUT, ">$dst";
      my $x = <IN>;
      while($x) {
        print OUT $x;
        $x = <IN>;
      }
    close OUT;
  close IN;
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
  "margin=s" => \$margin,
  "verbose"  => \$verbose,
  "copy"     => \$copy,
  "symlink"  => \$symlink,
  "hardlink" => \$hardlink,
  "ext=s"      => \$ext,
);

@srcdir = @ARGV;
$dstdir = pop @srcdir;
$margin ||= 1024**2;
$ext{$_}++ for split /,/, $ext;
initialstate();
# Copy new files
while ( my $file = nextfile(\@newfiles) ) {
  makespace($file);
  copyfile($file);
}
# Delete all old ones
#print "Deleting remaining old ones";
while ( my $file = nextfile(\@oldfiles) ) {
  delfile($file->{name});
}

