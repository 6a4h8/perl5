#!./perl -w

BEGIN {
   if( $ENV{PERL_CORE} ) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use strict;
use warnings;

use Test::More;

my $TB = Test::More->builder;

plan tests => 91;

# We're going to override rename() later on but Perl has to see an override
# at compile time to honor it.
BEGIN { *CORE::GLOBAL::rename = sub { CORE::rename($_[0], $_[1]) }; }


use File::Copy;
use Config;


foreach my $code ("copy()", "copy('arg')", "copy('arg', 'arg', 'arg', 'arg')",
                  "move()", "move('arg')", "move('arg', 'arg', 'arg')"
                 )
{
    eval $code;
    like $@, qr/^Usage: /, "'$code' is a usage error";
}


for my $cross_partition_test (0..1) {
  {
    # Simulate a cross-partition copy/move by forcing rename to
    # fail.
    no warnings 'redefine';
    *CORE::GLOBAL::rename = sub { 0 } if $cross_partition_test;
  }

  # First we create a file
  open(F, ">file-$$") or die $!;
  binmode F; # for DOSISH platforms, because test 3 copies to stdout
  printf F "ok\n";
  close F;

  copy "file-$$", "copy-$$";

  open(F, "copy-$$") or die $!;
  my $foo = <F>;
  close(F);

  is -s "file-$$", -s "copy-$$", 'copy(fn, fn): files of the same size';

  is $foo, "ok\n", 'copy(fn, fn): same contents';

  print("# next test checks copying to STDOUT\n");
  binmode STDOUT unless $^O eq 'VMS'; # Copy::copy works in binary mode
  # This outputs "ok" so its a test.
  copy "copy-$$", \*STDOUT;
  $TB->current_test($TB->current_test + 1);
  unlink "copy-$$" or die "unlink: $!";

  open(F,"file-$$");
  copy(*F, "copy-$$");
  open(R, "copy-$$") or die "open copy-$$: $!"; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(*F, fn): same contents';
  unlink "copy-$$" or die "unlink: $!";

  open(F,"file-$$");
  copy(\*F, "copy-$$");
  close(F) or die "close: $!";
  open(R, "copy-$$") or die; $foo = <R>; close(R) or die "close: $!";
  is $foo, "ok\n", 'copy(\*F, fn): same contents';
  unlink "copy-$$" or die "unlink: $!";

  require IO::File;
  my $fh = IO::File->new(">copy-$$") or die "Cannot open copy-$$:$!";
  binmode $fh or die $!;
  copy("file-$$",$fh);
  $fh->close or die "close: $!";
  open(R, "copy-$$") or die; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(fn, io): same contents';
  unlink "copy-$$" or die "unlink: $!";

  require FileHandle;
  $fh = FileHandle->new(">copy-$$") or die "Cannot open copy-$$:$!";
  binmode $fh or die $!;
  copy("file-$$",$fh);
  $fh->close;
  open(R, "copy-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(fn, fh): same contents';
  unlink "file-$$" or die "unlink: $!";

  ok !move("file-$$", "copy-$$"), "move on missing file";
  ok -e "copy-$$",                '  target still there';

  # Doesn't really matter what time it is as long as its not now.
  my $time = 1000000000;
  utime( $time, $time, "copy-$$" );

  # Recheck the mtime rather than rely on utime in case we're on a
  # system where utime doesn't work or there's no mtime at all.
  # The destination file will reflect the same difficulties.
  my $mtime = (stat("copy-$$"))[9];

  ok move("copy-$$", "file-$$"), 'move';
  ok -e "file-$$",              '  destination exists';
  ok !-e "copy-$$",              '  source does not';
  open(R, "file-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'contents preserved';

  TODO: {
    local $TODO = 'mtime only preserved on ODS-5 with POSIX dates and DECC$EFS_FILE_TIMESTAMPS enabled' if $^O eq 'VMS';

    my $dest_mtime = (stat("file-$$"))[9];
    is $dest_mtime, $mtime,
      "mtime preserved by copy()". 
      ($cross_partition_test ? " while testing cross-partition" : "");
  }

  # trick: create lib/ if not exists - not needed in Perl core
  unless (-d 'lib') { mkdir 'lib' or die $!; }
  copy "file-$$", "lib";
  open(R, "lib/file-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(fn, dir): same contents';
  unlink "lib/file-$$" or die "unlink: $!";

  # Do it twice to ensure copying over the same file works.
  copy "file-$$", "lib";
  open(R, "lib/file-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy over the same file works';
  unlink "lib/file-$$" or die "unlink: $!";

  { 
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= join '', @_ };
    ok copy("file-$$", "file-$$"), 'copy(fn, fn) succeeds';

    like $warnings, qr/are identical/, 'but warns';
    ok -s "file-$$", 'contents preserved';
  }

  move "file-$$", "lib";
  open(R, "lib/file-$$") or die "open lib/file-$$: $!"; $foo = <R>; close(R);
  is $foo, "ok\n", 'move(fn, dir): same contents';
  ok !-e "file-$$", 'file moved indeed';
  unlink "lib/file-$$" or die "unlink: $!";

  SKIP: {
    skip "Testing symlinks", 3 unless $Config{d_symlink};

    open(F, ">file-$$") or die $!;
    print F "dummy content\n";
    close F;
    symlink("file-$$", "symlink-$$") or die $!;

    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= join '', @_ };
    ok !copy("file-$$", "symlink-$$"), 'copy to itself (via symlink) fails';

    like $warnings, qr/are identical/, 'emits a warning';
    ok !-z "file-$$", 
      'rt.perl.org 5196: copying to itself would truncate the file';

    unlink "symlink-$$" or die $!;
    unlink "file-$$" or die $!;
  }

  SKIP: {
    skip "Testing hard links", 3 
         if !$Config{d_link} or $^O eq 'MSWin32' or $^O eq 'cygwin';

    open(F, ">file-$$") or die $!;
    print F "dummy content\n";
    close F;
    link("file-$$", "hardlink-$$") or die $!;

    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= join '', @_ };
    ok !copy("file-$$", "hardlink-$$"), 'copy to itself (via hardlink) fails';

    like $warnings, qr/are identical/, 'emits a warning';
    ok ! -z "file-$$",
      'rt.perl.org 5196: copying to itself would truncate the file';

    unlink "hardlink-$$" or die $!;
    unlink "file-$$" or die $!;
  }

  open(F, ">file-$$") or die $!;
  binmode F;
  print F "this is file\n";
  close F;

  my $copy_msg = "this is copy\n";
  open(F, ">copy-$$") or die $!;
  binmode F;
  print F $copy_msg;
  close F;

  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, join '', @_ };

  # pie-$$ so that we force a non-constant, else the numeric conversion (of 0)
  # is cached and we don't get a warning the second time round
  is eval { copy("file-$$", "copy-$$", "pie-$$"); 1 }, undef,
    "a bad buffer size fails to copy";
  like $@, qr/Bad buffer size for copy/, "with a helpful error message";
  unless (is scalar @warnings, 1, "There is 1 warning") {
    diag $_ foreach @warnings;
  }

  is -s "copy-$$", length $copy_msg, "but does not truncate the destination";
  open(F, "copy-$$") or die $!;
  $foo = <F>;
  close(F);
  is $foo, $copy_msg, "nor change the destination's contents";

  unlink "file-$$" or die $!;
  unlink "copy-$$" or die $!;
}


{
    # Just a sub to get better failure messages.
    sub __ ($) {
        join "" => map {(qw [--- --x -w- -wx r-- r-x rw- rwx]) [$_]} 
                   split // => sprintf "%03o" => shift
    }
    # Testing permission bits.
    my $src   = "file-$$";
    my $copy1 = "copy1-$$";
    my $copy2 = "copy2-$$";
    my $copy3 = "copy3-$$";

    open my $fh => ">", $src   or die $!;
    close   $fh                or die $!;

    open    $fh => ">", $copy3 or die $!;
    close   $fh                or die $!;

    my @tests = (
        [0000,  0777,  0777,  0777],
        [0000,  0751,  0751,  0644],
        [0022,  0777,  0755,  0206],
        [0022,  0415,  0415,  0666],
        [0077,  0777,  0700,  0333],
        [0027,  0755,  0750,  0251],
        [0777,  0751,  0000,  0215],
    );
    my $old_mask = umask;
    foreach my $test (@tests) {
        my ($umask, $s_perm, $c_perm1, $c_perm3) = @$test;
        # Make sure the copies doesn't exist.
        ! -e $_ or unlink $_ or die $! for $copy1, $copy2;

       (umask $umask) // die $!;
        chmod $s_perm  => $src   or die $!;
        chmod $c_perm3 => $copy3 or die $!;

        open my $fh => "<", $src or die $!;

        copy ($src, $copy1);
        copy ($fh,  $copy2);
        copy ($src, $copy3);

        my $perm1 = (stat $copy1) [2] & 0xFFF;
        my $perm2 = (stat $copy2) [2] & 0xFFF;
        my $perm3 = (stat $copy3) [2] & 0xFFF;
        is (__$perm1, __$c_perm1, "Permission bits set correctly");
        is (__$perm2, __$c_perm1, "Permission bits set correctly");
        is (__$perm3, __$c_perm3, "Permission bits not modified");
    }
    umask $old_mask or die $!;

    # Clean up.
    ! -e $_ or unlink $_ or die $! for $src, $copy1, $copy2, $copy3;
}


END {
    1 while unlink "file-$$";
    1 while unlink "lib/file-$$";
}
