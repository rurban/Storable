;# $Id: Storable.pm,v 0.4.1.2 1997/02/27 14:57:42 ram Exp $
;#
;#  Copyright (c) 1995-1997, Raphael Manfredi
;#  
;#  You may redistribute only under the terms of the Artistic License,
;#  as specified in the README file that comes with the distribution.
;#
;# $Log: Storable.pm,v $
;# Revision 0.4.1.2  1997/02/27  14:57:42  ram
;# patch3: added VERSION identification
;#
;# Revision 0.4.1.1  1997/01/22  14:17:19  ram
;# patch1: documented new forgive_me variable
;#
;# Revision 0.4  1997/01/15  18:20:09  ram
;# Baseline for fourth netwide alpha release.
;#

require DynaLoader;
require Exporter;
package Storable; @ISA = qw(Exporter DynaLoader);

@EXPORT = qw(store retrieve);
@EXPORT_OK = qw(nstore store_fd nstore_fd retrieve_fd);

use AutoLoader;
use Carp;
use vars qw($forgive_me);

$VERSION = '0.4_03';

bootstrap Storable;
1;
__END__

#
# store
#
# Store target object hierarchy, identified by a reference to its root.
# The stored object tree may later be retrieved to memory via retrieve.
# Returns undef if an I/O error occurred, in which case the file is
# removed.
#
sub store {
	return _store(0, @_);
}

#
# nstore
#
# Same as store, but in network order.
#
sub nstore {
	return _store(1, @_);
}

# Internal store routine
sub _store {
	my $netorder = shift;
	my $self = shift;
	my ($file) = @_;
	croak "Not a reference" unless ref($self);
	croak "Too many arguments" unless @_ == 1;	# Watch out for @foo in arglist
	local *FILE;
	open(FILE, ">$file") || croak "Can't create $file: $!";
	my $ret;
	# Call C routine nstore or pstore, depending on network order
	eval { $ret = $netorder ? net_pstore(FILE, $self) : pstore(FILE, $self) };
	close(FILE) or $ret = undef;
	unlink($file) or warn "Can't unlink $file: $!\n" if $@ || !defined $ret;
	croak $@ if $@ =~ s/\.?\n$/,/;
	return $ret ? $ret : undef;
}

#
# store_fd
#
# Same as store, but perform on an already opened file descriptor instead.
# Returns undef if an I/O error occurred.
#
sub store_fd {
	return _store_fd(0, @_);
}

#
# nstore_fd
#
# Same as store_fd, but in network order.
#
sub nstore_fd {
	my ($self, $file) = @_;
	return _store_fd(1, @_);
}

# Internal store routine
sub _store_fd {
	my $netorder = shift;
	my $self = shift;
	my ($file) = @_;
	croak "Not a reference" unless ref($self);
	croak "Too many arguments" unless @_ == 1;	# Watch out for @foo in arglist
	my $fd = fileno($file);
	croak "Not a valid file descriptor" unless defined $fd;
	my $ret;
	# Call C routine nstore or pstore, depending on network order
	eval { $ret = $netorder ? net_pstore($file, $self) : pstore($file, $self) };
	croak $@ if $@ =~ s/\.?\n$/,/;
	return $ret ? $ret : undef;
}

#
# retrieve
#
# Retrieve object hierarchy from disk, returning a reference to the root
# object of that tree.
#
sub retrieve {
	my ($file) = @_;
	local *FILE;
	open(FILE, "$file") || croak "Can't open $file: $!";
	my $self;
	eval { $self = pretrieve(FILE) };		# Call C routine
	close(FILE);
	croak $@ if $@ =~ s/\.?\n$/,/;
	return $self;
}

#
# retrieve_fd
#
# Same as retrieve, but perform from an already opened file descriptor instead.
#
sub retrieve_fd {
	my ($file) = @_;
	my $fd = fileno($file);
	croak "Not a valid file descriptor" unless defined $fd;
	my $self;
	eval { $self = pretrieve($file) };		# Call C routine
	croak $@ if $@ =~ s/\.?\n$/,/;
	return $self;
}

=head1 NAME

Storable - persistency for perl data structures

=head1 SYNOPSIS

	use Storable;
	store \%table, 'file';
	$hashref = retrieve('file');

=head1 DESCRIPTION

The Storable package brings you persistency for your perl data structures
containing SCALAR, ARRAY, HASH or REF objects, i.e. anything that can be
convenientely stored to disk and retrieved at a later time.

It can be used in the regular procedural way by calling C<store> with
a reference to the object to store, and providing a file name. The routine
returns C<undef> for I/O problems or other internal error, a true value
otherwise. Serious errors are propagated as a C<die> exception.

To retrieve data stored to disk, you use C<retrieve> with a file name,
and the objects stored into that file are recreated into memory for you,
and a I<reference> to the root object is returned. In case an I/O error
occurred while reading, C<undef> is returned instead. Other serious
errors are propagated via C<die>.

Since storage is performed recursively, you might want to stuff references
to objects that share a lot of common data into a single array or hash
table, and then store that object. That way, when you retrieve back the
whole thing, the objects will continue to share what they originally shared.

At the cost of a slight header overhead, you may store to an already
opened file descriptor using the C<store_fd> routine, and retrieve
from a file via C<retrieve_fd>. Those names aren't imported by default,
so you will have to do that explicitely if you need those routines.
The file descriptor name you supply must be fully qualified.

You can also store data in network order to allow easy sharing across
multiple platforms, or when storing on a socket known to be remotely
connected. The routines to call have an initial C<n> prefix for I<network>,
as in C<nstore> and C<nstore_fd>. At retrieval time, your data will be
correctly restored so you don't have to know whether you're restoring
from native or network ordered data.

When using C<retrieve_fd>, objects are retrieved in sequence, one
object (i.e. one recursive tree) per associated C<store_fd>.

If you're more from the object-oriented camp, you can inherit from
Storable and directly store your objects by invoking C<store> as
a method. The fact that the root of the to-be-stored tree is a
blessed reference (i.e. an object) is special-cased so that the
retrieve does not provide a reference to that object but rather the
blessed object reference itself. (Otherwise, you'd get a reference
to that blessed object).

=head1 SPEED

The heart of Storable is written in C for decent speed. Extra low-level
optimization have been made when manipulating perl internals, to
sacrifice encapsulation for the benefit of a greater speed.

Storage is usually faster than retrieval since the latter has to
allocate the objects from memory and perform the relevant I/Os, whilst
the former mainly performs I/Os.

On my HP 9000/712 machine running HPUX 9.03, I can store 1 Mbyte/s
and I can retrieve at 0.86 Mbytes/s, approximatively
(CPU + system time).
This was measured with Benchmark and the I<Magic: The Gathering>
database from Tom Christiansen (1.9 Mbytes).

=head1 WARNING

If you're using references as keys within your hash tables, you're bound
to disapointment when retrieving your data. Indeed, Perl stringifies
references used as hash table keys. If you later wish to access the
items via another reference stringification (i.e. using the same
reference that was used for the key originally to record the value into
the hash table), it will work because both references stringify to the
same string.

It won't work across a C<store> and C<retrieve> operations however, because
the addresses in the retrieved objects, which are part of the stringified
references, will probably differ from the original addresses. The
topology of your structure is preserved, but not hidden semantics
like those.

=head1 BUGS

You can't store GLOB, CODE, FORMLINE, etc... If you can define
semantics for those operations, feel free to enhance Storable so that
it can deal with those.

The store functions will C<croak> if they run into such references
unless you set C<$Storable::forgive_me> to some C<TRUE> value. In this
case, the fatal message is turned in a warning and some
meaningless string is stored instead.

Due to the aforementionned optimizations, Storable is at the mercy
of perl's internal redesign or structure changes. If that bothers
you, you can try convincing Larry that what is used in Storable
should be documented and consistently kept in future revisions.
As I said, you may try.

=head1 AUTHOR

Raphael Manfredi F<E<lt>Raphael_Manfredi@grenoble.hp.comE<gt>>

=cut
