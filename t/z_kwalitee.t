# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Config;
use File::Copy qw(cp mv);

plan skip_all => 'requires Test::More 0.88' if Test::More->VERSION < 0.88;

plan skip_all => 'This test is only run for the module author'
  unless -d '.git' || $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

# Missing XS dependencies are usually not caught by EUMM
# And they are usually only XS-loaded by the importer, not require.
for (qw( Class::XSAccessor Text::CSV_XS List::MoreUtils )) {
  eval "use $_;";
  plan skip_all => "$_ required for Test::Kwalitee"
    if $@;
}
eval "require Test::Kwalitee;";
plan skip_all => "Test::Kwalitee required"
  if $@;

plan skip_all => 'Test::Kwalitee fails with clang -faddress-sanitizer'
  if $Config{ccflags} =~ /-faddress-sanitizer/;

# Test::Kwalitee has a problem with the generated module. It is in MANIFEST.SKIP
# hence Kwalitee skips it, but then some tests fail:
#   -has_license_in_source_file -has_abstract_in_pod
# And I don't care for use strict in the generated Limit.pm
# hack: https://rt.cpan.org/Ticket/Display.html?id=128724
cp 'MANIFEST.SKIP', 'MANIFEST.SKIP~';
`grep -v Storable.pm MANIFEST.SKIP~ >MANIFEST.SKIP`;
Test::Kwalitee->import( tests => [ qw( -use_strict -has_buildtool ) ] );
mv 'MANIFEST.SKIP~', 'MANIFEST.SKIP';
