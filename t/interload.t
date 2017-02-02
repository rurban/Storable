#!./perl -w
#
#  Copyright 2017, cPanel Inc
#
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#

# This test checks loading previously incompatible data, on different sizes
# and byteorder.

sub BEGIN {
    unshift @INC, 't';
    unshift @INC, 't/compat' if $] < 5.006002;
    require Config; import Config;
    if ($ENV{PERL_CORE} and $Config{'extensions'} !~ /\bStorable\b/) {
        print "1..0 # Skip: Storable was not built\n";
        exit 0;
    }
}

use Test::More;
use Storable 'thaw';

use strict;
use vars qw(@RESTRICT_TESTS %R_HASH %U_HASH $UTF8_CROAK $RESTRICTED_CROAK);

@RESTRICT_TESTS = ('Locked hash', 'Locked hash placeholder',
                   'Locked keys', 'Locked keys placeholder',
                  );
%R_HASH = (cperl => 'rules');

if ($] > 5.007002) {
  # This is cheating. "\xdf" in Latin 1 is beta S, so will match \w if it
  # is stored in utf8, not bytes.
  # "\xdf" is y diaresis in EBCDIC (except for cp875, but so far no-one seems
  # to use that) which has exactly the same properties for \w
  # So the tests happen to pass.
  my $utf8 = "Schlo\xdf" . chr 256;
  chop $utf8;

  # \xe5 is V in EBCDIC. That doesn't have the same properties w.r.t. \w as
  # an a circumflex, so we need to be explicit.

  # and its these very properties we're trying to test - an edge case
  # involving whether scalars are being stored in bytes or in utf8.
  my $a_circumflex = (ord ('A') == 193 ? "\x47" : "\xe5");
  %U_HASH = (map {$_, $_} 'castle', "ch${a_circumflex}teau", $utf8, chr 0x57CE);
  plan tests => 146;
} elsif ($] >= 5.006) {
  plan tests => 59;
} else {
  plan tests => 67;
}

$UTF8_CROAK = "/^Cannot retrieve UTF8 data in non-UTF8 perl/";
$RESTRICTED_CROAK = "/^Cannot retrieve restricted hash/";

my %tests;
{
  local $/ = "\n\nend\n";
  while (<DATA>) {
    next unless /\S/s;
    unless (/begin ([0-7]{3}) ([^\n]*)\n(.*)$/s) {
      s/\n.*//s;
      warn "Dodgy data in section starting '$_'";
      next;
    }
    next unless oct $1 == ord 'A'; # Skip ASCII on EBCDIC, and vice versa
    my $data = unpack 'u', $3;
    $tests{$2} = $data;
  }
}

# use Data::Dumper; $Data::Dumper::Useqq = 1; print Dumper \%tests;
sub thaw_hash {
  my ($name, $expected) = @_;
  my $hash = eval {thaw $tests{$name}};
  is ($@, '', "Thawed $name without error?");
  isa_ok ($hash, 'HASH');
  ok (defined $hash && eq_hash($hash, $expected),
      "And it is the hash we expected?");
  $hash;
}

sub thaw_scalar {
  my ($name, $expected, $bug) = @_;
  my $scalar = eval {thaw $tests{$name}};
  is ($@, '', "Thawed $name without error?");
  isa_ok ($scalar, 'SCALAR', "Thawed $name?");
  if ($bug and $] == 5.006) {
    # Aargh. <expletive> <expletive> 5.6.0's harness doesn't even honour
    # TODO tests.
    warn "# Test skipped because eq is buggy for certain Unicode cases in 5.6.0";
    warn "# Please upgrade to 5.6.1\n";
    ok ("I'd really like to fail this test on 5.6.0 but I'm told that CPAN auto-dependencies mess up, and certain vendors only ship 5.6.0. Get your vendor to ugrade. Else upgrade your vendor.");
    # One such vendor being the folks who brought you LONG_MIN as a positive
    # integer.
  } else {
    is ($$scalar, $expected, "And it is the data we expected?");
  }
  $scalar;
}

sub thaw_fail {
  my ($name, $expected) = @_;
  my $thing = eval {thaw $tests{$name}};
  is ($thing, undef, "Thawed $name failed as expected?");
  like ($@, $expected, "Error as predicted?");
}

sub test_locked_hash {
  my $hash = shift;
  my @keys = keys %$hash;
  my ($key, $value) = each %$hash;
  eval {$hash->{$key} = reverse $value};
  like( $@, "/^Modification of a read-only value attempted/",
        'trying to change a locked key' );
  is ($hash->{$key}, $value, "hash should not change?");
  eval {$hash->{use} = 'cperl'};
  like( $@, "/^Attempt to access disallowed key 'use' in a restricted hash/",
        'trying to add another key' );
  ok (eq_array([keys %$hash], \@keys), "Still the same keys?");
}

sub test_restricted_hash {
  my $hash = shift;
  my @keys = keys %$hash;
  my ($key, $value) = each %$hash;
  eval {$hash->{$key} = reverse $value};
  is( $@, '',
        'trying to change a restricted key' );
  is ($hash->{$key}, reverse ($value), "hash should change");
  eval {$hash->{use} = 'cperl'};
  like( $@, "/^Attempt to access disallowed key 'use' in a restricted hash/",
        'trying to add another key' );
  ok (eq_array([keys %$hash], \@keys), "Still the same keys?");
}

sub test_placeholder {
  my $hash = shift;
  eval {$hash->{rules} = 42};
  is ($@, '', 'No errors');
  is ($hash->{rules}, 42, "New value added");
}

sub test_newkey {
  my $hash = shift;
  eval {$hash->{nms} = "http://nms-cgi.sourceforge.net/"};
  is ($@, '', 'No errors');
  is ($hash->{nms}, "http://nms-cgi.sourceforge.net/", "New value added");
}

# $Storable::DEBUGME = 1;
thaw_hash ('Hash with utf8 flag but no utf8 keys', \%R_HASH);

if (eval "use Hash::Util; 1") {
  print "# We have Hash::Util, so test that the restricted hashes in <DATA> are valid\n";
  for my $bit ("32bit", "64bit") {
    for $Storable::downgrade_restricted (0, 1, undef, "cheese") {
      my $hash = thaw_hash ("$bit Locked hash", \%R_HASH);
      test_locked_hash ($hash);
      $hash = thaw_hash ("$bit Locked hash placeholder", \%R_HASH);
      test_locked_hash ($hash);
      test_placeholder ($hash);

      $hash = thaw_hash ("$bit Locked keys", \%R_HASH);
      test_restricted_hash ($hash);
      $hash = thaw_hash ("$bit Locked keys placeholder", \%R_HASH);
      test_restricted_hash ($hash);
      test_placeholder ($hash);
    }
  }
} else {
  print "# We don't have Hash::Util, so test that the restricted hashes downgrade\n";
  for my $bit ("32bit", "64bit") {
    my $hash = thaw_hash ("$bit Locked hash", \%R_HASH);
    test_newkey ($hash);
    $hash = thaw_hash ("$bit Locked hash placeholder", \%R_HASH);
    test_newkey ($hash);
    $hash = thaw_hash ("$bit Locked keys", \%R_HASH);
    test_newkey ($hash);
    $hash = thaw_hash ("$bit Locked keys placeholder", \%R_HASH);
    test_newkey ($hash);
    local $Storable::downgrade_restricted = 0;
    thaw_fail ("$bit Locked hash", $RESTRICTED_CROAK);
    thaw_fail ("$bit Locked hash placeholder", $RESTRICTED_CROAK);
    thaw_fail ("$bit Locked keys", $RESTRICTED_CROAK);
    thaw_fail ("$bit Locked keys placeholder", $RESTRICTED_CROAK);
  }
}

if ($] >= 5.006) {
  print "# We have utf8 scalars, so test that the utf8 scalars in <DATA> are valid\n";
  for my $bit ("32bit", "64bit") {
    thaw_scalar ("$bit Short 8 bit utf8 data", "\xDF", 1);
    thaw_scalar ("$bit Long 8 bit utf8 data", "\xDF" x 256, 1);
    thaw_scalar ("$bit Short 24 bit utf8 data", chr 0xC0FFEE);
    thaw_scalar ("$bit Long 24 bit utf8 data", chr (0xC0FFEE) x 256);
  }
} else {
  print "# We don't have utf8 scalars, so test that the utf8 scalars downgrade\n";
  for my $bit ("32bit", "64bit") {
    thaw_fail ("$bit Short 8 bit utf8 data", $UTF8_CROAK);
    thaw_fail ("$bit Long 8 bit utf8 data", $UTF8_CROAK);
    thaw_fail ("$bit Short 24 bit utf8 data", $UTF8_CROAK);
    thaw_fail ("$bit Long 24 bit utf8 data", $UTF8_CROAK);
    local $Storable::drop_utf8 = 1;
    my $bytes = thaw $tests{"$bit Short 8 bit utf8 data as bytes"};
    thaw_scalar ("$bit Short 8 bit utf8 data", $$bytes);
    thaw_scalar ("$bit Long 8 bit utf8 data", $$bytes x 256);
    $bytes = thaw $tests{"$bit Short 24 bit utf8 data as bytes"};
    thaw_scalar ("$bit Short 24 bit utf8 data", $$bytes);
    thaw_scalar ("$bit Long 24 bit utf8 data", $$bytes x 256);
  }
}

if ($] > 5.007002) {
  print "# We have utf8 hashes, so test that the utf8 hashes in <DATA> are valid\n";
  my $a_circumflex = (ord ('A') == 193 ? "\x47" : "\xe5");
  for my $bit ("32bit", "64bit") {
     my $hash = thaw_hash ("$bit Hash with utf8 keys", \%U_HASH);
     for (keys %$hash) {
       my $l = 0 + /^\w+$/;
       my $r = 0 + $hash->{$_} =~ /^\w+$/;
       cmp_ok ($l, '==', $r, sprintf "key length %d", length $_);
       cmp_ok ($l, '==', $_ eq "ch${a_circumflex}teau" ? 0 : 1);
     }
  }
  if (eval "use Hash::Util; 1") {
    print "# We have Hash::Util, so test that the restricted utf8 hash is valid\n";
    for my $bit ("32bit", "64bit") {
      my $hash = thaw_hash ("$bit Locked hash with utf8 keys", \%U_HASH);
      for (keys %$hash) {
        my $l = 0 + /^\w+$/;
        my $r = 0 + $hash->{$_} =~ /^\w+$/;
        cmp_ok ($l, '==', $r, sprintf "key length %d", length $_);
        cmp_ok ($l, '==', $_ eq "ch${a_circumflex}teau" ? 0 : 1);
      }
      test_locked_hash ($hash);
    }
  } else {
    print "# We don't have Hash::Util, so test that the utf8 hash downgrades\n";
    fail ("You can't get here [perl version $]]. This is a bug in the test.
# Please send the output of perl -V to perlbug\@perl.org");
  }
} else {
  print "# We don't have utf8 hashes, so test that the utf8 hashes downgrade\n";
  for my $bit ("32bit", "64bit") {
    thaw_fail ("$bit Hash with utf8 keys", $UTF8_CROAK);
    thaw_fail ("$bit Locked hash with utf8 keys", $UTF8_CROAK);
    local $Storable::drop_utf8 = 1;
    my $what = $] < 5.006 ? 'pre 5.6' : '5.6';
    my $expect = thaw $tests{"$bit Hash with utf8 keys for $what"};
    thaw_hash ("$bit Hash with utf8 keys", $expect);
    #foreach (keys %$expect) { print "'$_':\t'$expect->{$_}'\n"; }
    #foreach (keys %$got) { print "'$_':\t'$got->{$_}'\n"; }
    if (eval "use Hash::Util; 1") {
      print "# We have Hash::Util, so test that the restricted hashes in <DATA> are valid\n";
      fail ("You can't get here [perl version $]]. This is a bug in the test.
            # Please send the output of perl -V to perlbug\@perl.org");
    } else {
      print "# We don't have Hash::Util, so test that the restricted hashes downgrade\n";
      my $hash = thaw_hash ("$bit Locked hash with utf8 keys", $expect);
      test_newkey ($hash);
      local $Storable::downgrade_restricted = 0;
      thaw_fail ("$bit Locked hash with utf8 keys", $RESTRICTED_CROAK);
      # Which croak comes first is a bit of an implementation issue :-)
      local $Storable::drop_utf8 = 0;
      thaw_fail ("$bit Locked hash with utf8 keys", $RESTRICTED_CROAK);
    }
  }
}

__END__
# A whole run of 3.x freeze and nfreeze data, uuencoded, for 32 and 64bit.
# generated with t/make_interload.pl on 32bit and 64bit machines
# The "mode bits" are the octal value of 'A', the "file name" is the test name.

begin 101 64bit Locked hash
9!0L9`0````$*!7)U;&5S!`````5C<&5R;```

end

begin 101 64bit Locked hash
F!`L(,3(S-#4V-S@$"`@(&0$!````"@5R=6QE<P0%````8W!E<FP`

end

begin 101 64bit Locked hash placeholder
9!0L9`0````$*!7)U;&5S!`````5C<&5R;```

end

begin 101 64bit Locked hash placeholder
F!`L(,3(S-#4V-S@$"`@(&0$!````"@5R=6QE<P0%````8W!E<FP`

end

begin 101 64bit Locked keys
9!0L9`0````$*!7)U;&5S``````5C<&5R;```

end

begin 101 64bit Locked keys
F!`L(,3(S-#4V-S@$"`@(&0$!````"@5R=6QE<P`%````8W!E<FP`

end

begin 101 64bit Locked keys placeholder
D!0L9`0````(.%`````5R=6QE<PH%<G5L97,`````!6-P97)L

end

begin 101 64bit Locked keys placeholder
M!`L(,3(S-#4V-S@$"`@(&0$"````#A0%````<G5L97,*!7)U;&5S``4```!C
$<&5R;```

end

begin 101 64bit Short 8 bit utf8 data
&!0L7`L.?

end

begin 101 64bit Short 8 bit utf8 data
3!`L(,3(S-#4V-S@$"`@(%P+#GP``

end

begin 101 64bit Short 8 bit utf8 data as bytes
&!0L*`L.?

end

begin 101 64bit Short 8 bit utf8 data as bytes
3!`L(,3(S-#4V-S@$"`@("@+#GP``

end

begin 101 64bit Long 8 bit utf8 data
M!0L8```"`,.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
8PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?

end

begin 101 64bit Long 8 bit utf8 data
M!`L(,3(S-#4V-S@$"`@(&``"``##G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
EG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#GP``

end

begin 101 64bit Short 24 bit utf8 data
)!0L7!?BPC[^N

end

begin 101 64bit Short 24 bit utf8 data
6!`L(,3(S-#4V-S@$"`@(%P7XL(^_K@``

end

begin 101 64bit Short 24 bit utf8 data as bytes
)!0L*!?BPC[^N

end

begin 101 64bit Short 24 bit utf8 data as bytes
6!`L(,3(S-#4V-S@$"`@("@7XL(^_K@``

end

begin 101 64bit Long 24 bit utf8 data
M!0L8```%`/BPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
;OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N

end

begin 101 64bit Long 24 bit utf8 data
M!`L(,3(S-#4V-S@$"`@(&``%``#XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
M^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N
H^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_K@``

end

begin 101 64bit Hash with utf8 flag but no utf8 keys
9!0L9``````$*!7)U;&5S``````5C<&5R;```

end

begin 101 64bit Hash with utf8 flag but no utf8 keys
F!`L(,3(S-#4V-S@$"`@(&0`!````"@5R=6QE<P`%````8W!E<FP`

end

begin 101 64bit Hash with utf8 keys
M!0L9``````07`^6?C@$````#Y9^.%P=38VAL;\.?`@````938VAL;]\*!F-A
D<W1L90`````&8V%S=&QE"@=C:.5T96%U``````=C:.5T96%U

end

begin 101 64bit Hash with utf8 keys
M!`L(,3(S-#4V-S@$"`@(&0`$````%P/EGXX!`P```.6?CA<'4V-H;&_#GP(&
M````4V-H;&_?"@9C87-T;&4`!@```&-A<W1L90H'8VCE=&5A=0`'````8VCE
$=&5A=0``

end

begin 101 64bit Locked hash with utf8 keys
M!0L9`0````07`^6?C@4````#Y9^.%P=38VAL;\.?!@````938VAL;]\*!F-A
D<W1L900````&8V%S=&QE"@=C:.5T96%U!`````=C:.5T96%U

end

begin 101 64bit Locked hash with utf8 keys
M!`L(,3(S-#4V-S@$"`@(&0$$````%P/EGXX%`P```.6?CA<'4V-H;&_#GP8&
M````4V-H;&_?"@9C87-T;&4$!@```&-A<W1L90H'8VCE=&5A=00'````8VCE
$=&5A=0``

end

begin 101 64bit Hash with utf8 keys for pre 5.6
M!0L9``````0*!U-C:&QOPY\"````!E-C:&QOWPH&8V%S=&QE``````9C87-T
D;&4*!V-HY71E874`````!V-HY71E874*`^6?C@`````#Y9^.

end

begin 101 64bit Hash with utf8 keys for pre 5.6
M!`L(,3(S-#4V-S@$"`@(&0`$````"@=38VAL;\.?`@8```!38VAL;]\*!F-A
M<W1L90`&````8V%S=&QE"@=C:.5T96%U``<```!C:.5T96%U"@/EGXX``P``
$`.6?C@``

end

begin 101 64bit Hash with utf8 keys for 5.6
M!0L9``````0*!F-A<W1L90`````&8V%S=&QE"@=C:.5T96%U``````=C:.5T
D96%U%P=38VAL;\.?`@````938VAL;]\7`^6?C@`````#Y9^.

end

begin 101 64bit Hash with utf8 keys for 5.6
M!`L(,3(S-#4V-S@$"`@(&0`$````"@9C87-T;&4`!@```&-A<W1L90H'8VCE
M=&5A=0`'````8VCE=&5A=1<'4V-H;&_#GP(&````4V-H;&_?%P/EGXX``P``
$`.6?C@``

end

begin 101 32bit Locked hash
9!0D9`0````$*!7)U;&5S!`````5C<&5R;```

end

begin 101 32bit Locked hash
B!`D$,3(S-`0$!`@9`0$````*!7)U;&5S!`4```!C<&5R;```

end

begin 101 32bit Locked hash placeholder
9!0D9`0````$*!7)U;&5S!`````5C<&5R;```

end

begin 101 32bit Locked hash placeholder
B!`D$,3(S-`0$!`@9`0$````*!7)U;&5S!`4```!C<&5R;```

end

begin 101 32bit Locked keys
9!0D9`0````$*!7)U;&5S``````5C<&5R;```

end

begin 101 32bit Locked keys
B!`D$,3(S-`0$!`@9`0$````*!7)U;&5S``4```!C<&5R;```

end

begin 101 32bit Locked keys placeholder
D!0D9`0````(*!7)U;&5S``````5C<&5R;`X4````!7)U;&5S

end

begin 101 32bit Locked keys placeholder
M!`D$,3(S-`0$!`@9`0(````*!7)U;&5S``4```!C<&5R;`X4!0```')U;&5S

end

begin 101 32bit Short 8 bit utf8 data
&!0D7`L.?

end

begin 101 32bit Short 8 bit utf8 data
/!`D$,3(S-`0$!`@7`L.?

end

begin 101 32bit Short 8 bit utf8 data as bytes
&!0D*`L.?

end

begin 101 32bit Short 8 bit utf8 data as bytes
/!`D$,3(S-`0$!`@*`L.?

end

begin 101 32bit Long 8 bit utf8 data
M!0D8```"`,.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
8PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?

end

begin 101 32bit Long 8 bit utf8 data
M!`D$,3(S-`0$!`@8``(``,.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
MG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?
MPY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#
AG\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?PY_#G\.?

end

begin 101 32bit Short 24 bit utf8 data
)!0D7!?BPC[^N

end

begin 101 32bit Short 24 bit utf8 data
2!`D$,3(S-`0$!`@7!?BPC[^N

end

begin 101 32bit Short 24 bit utf8 data as bytes
)!0D*!?BPC[^N

end

begin 101 32bit Short 24 bit utf8 data as bytes
2!`D$,3(S-`0$!`@*!?BPC[^N

end

begin 101 32bit Long 24 bit utf8 data
M!0D8```%`/BPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
MOZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/
;OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N

end

begin 101 32bit Long 24 bit utf8 data
M!`D$,3(S-`0$!`@8``4``/BPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
MKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_
DKOBPC[^N^+"/OZ[XL(^_KOBPC[^N^+"/OZ[XL(^_KOBPC[^N

end

begin 101 32bit Hash with utf8 flag but no utf8 keys
9!0D9``````$*!7)U;&5S``````5C<&5R;```

end

begin 101 32bit Hash with utf8 flag but no utf8 keys
B!`D$,3(S-`0$!`@9``$````*!7)U;&5S``4```!C<&5R;```

end

begin 101 32bit Hash with utf8 keys
M!0D9``````0*!F-A<W1L90`````&8V%S=&QE%P=38VAL;\.?`@````938VAL
D;]\7`^6?C@$````#Y9^."@=C:.5T96%U``````=C:.5T96%U

end

begin 101 32bit Hash with utf8 keys
M!`D$,3(S-`0$!`@9``0````*!F-A<W1L90`&````8V%S=&QE%P=38VAL;\.?
M`@8```!38VAL;]\7`^6?C@$#````Y9^."@=C:.5T96%U``<```!C:.5T96%U

end

begin 101 32bit Locked hash with utf8 keys
M!0D9`0````0*!F-A<W1L900````&8V%S=&QE%P=38VAL;\.?!@````938VAL
D;]\7`^6?C@4````#Y9^."@=C:.5T96%U!`````=C:.5T96%U

end

begin 101 32bit Locked hash with utf8 keys
M!`D$,3(S-`0$!`@9`00````*!F-A<W1L900&````8V%S=&QE%P=38VAL;\.?
M!@8```!38VAL;]\7`^6?C@4#````Y9^."@=C:.5T96%U!`<```!C:.5T96%U

end

begin 101 32bit Hash with utf8 keys for pre 5.6
M!0D9``````0*!F-A<W1L90`````&8V%S=&QE"@=38VAL;\.?`@````938VAL
D;]\*`^6?C@`````#Y9^."@=C:.5T96%U``````=C:.5T96%U

end

begin 101 32bit Hash with utf8 keys for pre 5.6
M!`D$,3(S-`0$!`@9``0````*!F-A<W1L90`&````8V%S=&QE"@=38VAL;\.?
M`@8```!38VAL;]\*`^6?C@`#````Y9^."@=C:.5T96%U``<```!C:.5T96%U

end

begin 101 32bit Hash with utf8 keys for 5.6
M!0D9``````0*!F-A<W1L90`````&8V%S=&QE%P=38VAL;\.?`@````938VAL
D;]\7`^6?C@`````#Y9^."@=C:.5T96%U``````=C:.5T96%U

end

begin 101 32bit Hash with utf8 keys for 5.6
M!`D$,3(S-`0$!`@9``0````*!F-A<W1L90`&````8V%S=&QE%P=38VAL;\.?
M`@8```!38VAL;]\7`^6?C@`#````Y9^."@=C:.5T96%U``<```!C:.5T96%U

end

