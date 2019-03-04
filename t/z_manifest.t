use strict;
use Test::More;
plan skip_all => 'This test is only run for the module author'
    unless -d '.git' || $ENV{AUTHOR_TESTING};
eval "use Test::CheckManifest;";
if ( $@ ) {
  plan( skip_all => "Test::CheckManifest not available for testing" );
  die "Failed to load required release-testing module Test::CheckManifest"
    if -d '.git' || $ENV{AUTHOR_TESTING};
}
ok_manifest();
