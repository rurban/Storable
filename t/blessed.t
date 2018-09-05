#!./perl
#
#  Copyright (c) 1995-2000, Raphael Manfredi
#  
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#

sub BEGIN {
    if ($ENV{PERL_CORE}) {
        chdir 'dist/Storable' if -d 'dist/Storable';
        @INC = ('../../lib', 't');
    } else {
        unshift @INC, 't';
        unshift @INC, 't/compat' if $] < 5.006002;
    }
    require Config; import Config;
    if ($ENV{PERL_CORE} and $Config{'extensions'} !~ /\bStorable\b/) {
        print "1..0 # Skip: Storable was not built\n";
        exit 0;
    }
}

use Test::More;

use Storable qw(freeze thaw store retrieve);

%::immortals =
    ('u' => \undef,
     'y' => \(!!1),  # yes
     'n' => \(!!0)   # no
);


%::weird_refs = 
  (REF            => \(my $aref    = []),
   VSTRING        => \(my $vstring = v1.2.3),
   'long VSTRING' => \(my $lvstring = eval "v" . 0 x 300),
   LVALUE         => \(my $substr  = substr((my $str = "foo"), 0, 3)));

my $test = 12;
my $tests = $test + 23 + (2 * 6 * keys %::immortals) + (3 * keys %::weird_refs);
plan(tests => $tests);

package SHORT_NAME;

sub make { bless [], shift }

package SHORT_NAME_WITH_HOOK;

sub make { bless [], shift }

sub STORABLE_freeze {
	my $self = shift;
	return ("", $self);
}

sub STORABLE_thaw {
	my $self = shift;
	my $cloning = shift;
	my ($x, $obj) = @_;
	die "STORABLE_thaw" unless $obj eq $self;
}

package main;

# Still less than 256 bytes, so long classname logic not fully exercised
#   Identifier too long - 5.004
#   parser.h: char	tokenbuf[256]: cperl5.24 => 1024
my $m = ($Config{usecperl} and $] >= 5.024) ? 56 : 14;
my $longname = "LONG_NAME_" . ('xxxxxxxxxxxxx::' x $m) . "final";

eval <<EOC;
package $longname;

\@ISA = ("SHORT_NAME");
EOC
is($@, '');

eval <<EOC;
package ${longname}_WITH_HOOK;

\@ISA = ("SHORT_NAME_WITH_HOOK");
EOC
is($@, '');

# Construct a pool of objects
my @pool;
for (my $i = 0; $i < 10; $i++) {
    push(@pool, SHORT_NAME->make);
    push(@pool, SHORT_NAME_WITH_HOOK->make);
    push(@pool, $longname->make);
    push(@pool, "${longname}_WITH_HOOK"->make);
}

my $x = freeze \@pool;
pass("Freeze didn't crash");

my $y = thaw $x;
is(ref $y, 'ARRAY');
is(scalar @{$y}, @pool);

is(ref $y->[0], 'SHORT_NAME');
is(ref $y->[1], 'SHORT_NAME_WITH_HOOK');
is(ref $y->[2], $longname);
is(ref $y->[3], "${longname}_WITH_HOOK");

my $good = 1;
for (my $i = 0; $i < 10; $i++) {
    do { $good = 0; last } unless ref $y->[4*$i]   eq 'SHORT_NAME';
    do { $good = 0; last } unless ref $y->[4*$i+1] eq 'SHORT_NAME_WITH_HOOK';
    do { $good = 0; last } unless ref $y->[4*$i+2] eq $longname;
    do { $good = 0; last } unless ref $y->[4*$i+3] eq "${longname}_WITH_HOOK";
}
is($good, 1);

{
    my $blessed_ref = bless \\[1,2,3], 'Foobar';
    my $x = freeze $blessed_ref;
    my $y = thaw $x;
    is(ref $y, 'Foobar');
    is($$$y->[0], 1);
}

package RETURNS_IMMORTALS;

sub make { my $self = shift; bless [@_], $self }

sub STORABLE_freeze {
    # Some reference some number of times.
    my $self = shift;
    my ($what, $times) = @$self;
    return ("$what$times", ($::immortals{$what}) x $times);
}

sub STORABLE_thaw {
    my $self = shift;
    my $cloning = shift;
    my ($x, @refs) = @_;
    my ($what, $times) = $x =~ /(.)(\d+)/;
    die "'$x' didn't match" unless defined $times;
    main::is(scalar @refs, $times);
    my $expect = $::immortals{$what};
    die "'$x' did not give a reference" unless ref $expect;
    my $fail;
    foreach (@refs) {
        $fail++ if $_ != $expect;
    }
  TODO: {
      # ref sv_true is not always sv_true, at least in older threaded perls.
      local $TODO = "Threaded 5.10/12 does not preserve sv_true ref identity"
        if $fail and $] < 5.013 and $] > 5.009 and $what eq 'y';
      main::is($fail, undef, "$x thaw"); # (@refs) == $expect
    }
}

package main;

# XXX Failed tests:  15, 27, 39 with 5.12 and 5.10 threaded.
# 15: 1 fail (y x 1), 27: 2 fail (y x 2), 39: 3 fail (y x 3)
my $count;
foreach $count (1..3) {
  #local $Storable::DEBUGME = 1;
  my $immortal;
  foreach $immortal (keys %::immortals) {
    print "# $immortal x $count\n";
    my $i =  RETURNS_IMMORTALS->make ($immortal, $count);

    my $f = freeze ($i);
  TODO: {
      # ref sv_true is not always sv_true, at least in older threaded perls.
      local $TODO = "Threaded 5.10/12 does not preserve sv_true ref identity"
        if !defined($f) and $] < 5.013 and $] > 5.009 and $immortal =~ /[yu]/;
      isnt($f, undef, "freeze $immortal x $count");
    }
    my $t = thaw $f;
    pass("thaw didn't crash");
  }
}

# Test automatic require of packages to find thaw hook.

package HAS_HOOK;

$loaded_count = 0;
$thawed_count = 0;

sub make {
  bless [];
}

sub STORABLE_freeze {
  my $self = shift;
  return '';
}

package main;

my $f = freeze (HAS_HOOK->make);

is($HAS_HOOK::loaded_count, 0);
is($HAS_HOOK::thawed_count, 0);

my $t = thaw $f;
is($HAS_HOOK::loaded_count, 1);
is($HAS_HOOK::thawed_count, 1);
isnt($t, undef);
is(ref $t, 'HAS_HOOK');

delete $INC{"HAS_HOOK.pm"};
delete $HAS_HOOK::{STORABLE_thaw};

$t = thaw $f;
is($HAS_HOOK::loaded_count, 2);
is($HAS_HOOK::thawed_count, 2);
isnt($t, undef);
is(ref $t, 'HAS_HOOK');

{
    package STRESS_THE_STACK;

    my $stress;
    sub make {
	bless [];
    }

    sub no_op {
	0;
    }

    sub STORABLE_freeze {
	my $self = shift;
	++$freeze_count;
	return no_op(1..(++$stress * 2000)) ? die "can't happen" : '';
    }

    sub STORABLE_thaw {
	my $self = shift;
	++$thaw_count;
	no_op(1..(++$stress * 2000)) && die "can't happen";
	return;
    }
}

$STRESS_THE_STACK::freeze_count = 0;
$STRESS_THE_STACK::thaw_count = 0;

$f = freeze (STRESS_THE_STACK->make);

is($STRESS_THE_STACK::freeze_count, 1);
is($STRESS_THE_STACK::thaw_count, 0);

$t = thaw $f;
is($STRESS_THE_STACK::freeze_count, 1);
is($STRESS_THE_STACK::thaw_count, 1);
isnt($t, undef);
is(ref $t, 'STRESS_THE_STACK');

my $file = "storable-testfile.$$";
die "Temporary file '$file' already exists" if -e $file;

END { while (-f $file) {unlink $file or die "Can't unlink '$file': $!" }}

$STRESS_THE_STACK::freeze_count = 0;
$STRESS_THE_STACK::thaw_count = 0;

store (STRESS_THE_STACK->make, $file);

is($STRESS_THE_STACK::freeze_count, 1);
is($STRESS_THE_STACK::thaw_count, 0);

$t = retrieve ($file);
is($STRESS_THE_STACK::freeze_count, 1);
is($STRESS_THE_STACK::thaw_count, 1);
isnt($t, undef);
is(ref $t, 'STRESS_THE_STACK');

{
    package ModifyARG112358;
    sub STORABLE_freeze { $_[0] = "foo"; }
    my $o= {str=>bless {}};
    my $f= ::freeze($o);
    ::is ref $o->{str}, __PACKAGE__,
	'assignment to $_[0] in STORABLE_freeze does not corrupt things';
}

# [perl #113880]
{
    {
        package WeirdRefHook;
        sub STORABLE_freeze { () }
        $INC{'WeirdRefHook.pm'} = __FILE__;
    }

    for my $weird (keys %weird_refs) {
        my $obj = $weird_refs{$weird};
        bless $obj, 'WeirdRefHook';
        my $frozen;
        my $success = eval { $frozen = freeze($obj); 1 };
        ok($success, "can freeze $weird objects")
            || diag("freezing failed: $@");
        my $thawn = thaw($frozen);
        # is_deeply ignores blessings
        is ref $thawn, ref $obj, "get the right blessing back for $weird";
        if ($weird =~ 'VSTRING') {
            # It is not just Storable that did not support vstrings. :-)
            # See https://rt.cpan.org/Ticket/Display.html?id=78678
            my $newver = "version"->can("new")
                           ? sub { "version"->new(shift) }
                           : sub { "" };
            if (!ok
                  $$thawn eq $$obj && &$newver($$thawn) eq &$newver($$obj),
                 "get the right value back"
            ) {
                diag "$$thawn vs $$obj";
                diag &$newver($$thawn) eq &$newver($$obj) if &$newver(1);
             }
        }
        else {
            is_deeply($thawn, $obj, "get the right value back");
        }
    }
}
