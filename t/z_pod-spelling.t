# -*- perl -*-
use strict;
use Test::More;

plan skip_all => 'This test is only run for the module author'
  unless -d '.git' || $ENV{AUTHOR_TESTING};

eval "use Test::Spelling;";
plan skip_all => "Test::Spelling required"
  if $@;

add_stopwords(<DATA>);
all_pod_files_spelling_ok();

__DATA__
CVE
Holzman
IPC
Lehmann
Manfredi
MERCHANTABILITY
Nesbitt
Reini
btw
de
eg
ie
interworking
metasploit
natively
tieing
CPAN
NFS
STDOUT
Storable
Storable's
deserialization
deserialize
deserialized
deserializes
deserializing
destructor
destructors
nd
precompiled
recurses
stringifies
utf
