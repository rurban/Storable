;# $Id: Storable.pm,v 0.1 1995/09/29 20:19:34 ram Exp $
;#
;#  Copyright (c) 1995, Raphael Manfredi
;#  
;#  You may redistribute only under the terms of the Artistic License,
;#  as specified in the README file that comes with the distribution.
;#
;# $Log: Storable.pm,v $
;# Revision 0.1  1995/09/29  20:19:34  ram
;# Baseline for first netwide alpha release.
;#

require DynaLoader;
require Exporter;
package Storable; @ISA = qw(Exporter DynaLoader);

@EXPORT = qw(store retrieve);
@EXPORT_OK = qw(store_fd retrieve_fd);

use AutoLoader;
use Carp;

bootstrap Storable;
1;
__END__

# Store target object hierarchy, identified by a reference to its root.
# The stored object tree may later be retrieved to memory via retrieve.
# Returns undef if an I/O error occurred, in which case the file is
# removed.
sub store {
	my $self = shift;
	my ($file) = @_;
	croak "Not a reference" unless ref($self);
	croak "Too many arguments" unless @_ == 1;	# Watch out for @foo in arglist
	local *FILE;
	open(FILE, ">$file") || croak "Can't create $file: $!";
	my $ret;
	eval { $ret = pstore(FILE, $self) };	# Call C routine
	close(FILE) or $ret = undef;
	unlink($file) or warn "Can't unlink $file: $!\n" if $@ || !defined $ret;
	croak $@ if $@ =~ s/\.?\n$/,/;
	return $ret ? $ret : undef;
}

# Same as store, but perform on an already opened file descriptor instead.
# Returns undef if an I/O error occurred.
sub store_fd {
	my $self = shift;
	my ($file) = @_;
	croak "Not a reference" unless ref($self);
	croak "Too many arguments" unless @_ == 1;	# Watch out for @foo in arglist
	my $fd = fileno($file);
	croak "Not a valid file descriptor" unless defined $fd;
	my $ret;
	eval { $ret = pstore($file, $self) };	# Call C routine
	croak $@ if $@ =~ s/\.?\n$/,/;
	return $ret ? $ret : undef;
}

# Retrieve object hierarchy from disk, returning a reference to the root
# object of that tree.
sub retrieve {
	my ($file) = @_;
	local *FILE;
	open(FILE, "$file") || croak "Can't open $file: $!";
	my $self;
	eval { $self = pretrieve(FILE) };		# Call C routine
	croak $@ if $@ =~ s/\.?\n$/,/;
	close(FILE);
	return $self;
}

# Same as retrieve, but perform from an already opened file descriptor instead.
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

When using C<retrieve_fd>, objects are retrieved in sequence, one
object (i.e. one recursive tree) per associated C<store_fd>.

If you're more from the object-oriented camp, you can inherit from
Storable and directly store your objects by invoking C<store> as
a method.

=head1 SPEED

The heart of Storable is written in C for decent speed. Extra low-level
optimization have been made when manipulating perl internals, to
sacrifice encapsulation for the benefit of a greater speed.

Storage is usually faster than retrieval since the latter has to
allocate the objects from memory and perform the relevant I/Os, whilst
the former mainly performs I/Os.

On my HPUX machine, I can store 200K in 0.8 seconds, and I can retrieve
the same data in 1.1 seconds, approximatively.

=head1 WARNING

If you're using references as keys within your hash tables, you're bound
to disapointment when retrieving your data. Indeed, Perl stringifies
references used as hash table keys. If you later wish to access the
items via another reference stringification (i.e. using the same
reference that was used for the key originally to record the value into
the hash table), it will work because both references stringify to the
same string.

It won't work accross a C<store> and C<retrieve> operations however, because
the addresses in the retrieved objects, which are part of the stringified
references, will probably differ from the original addresses. The
topology of your structure is preserved, but not hidden semantics
like those.

=head1 BUGS

You can't store GLOB, CODE, FORMLINE, etc... If you can define
semantics for those operations, feel free to enhance Storable so that
it can deal with those.

Due to the aforementionned optimizations, Storable is at the mercy
of perl's internal redesign or structure changes. If that bothers
you, you can try convincing Larry that what is used in Storable
should be documented and consistently kept in future revisions.
As I said, you may try.

=head1 AUTHOR

Raphael Manfredi F<E<lt>ram@hptnos02.grenoble.hp.comE<gt>>

=cut
