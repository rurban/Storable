/*
 * Store and retrieve mechanism.
 */

/*
 * $Id: Storable.xs,v 0.1 1995/09/29 20:19:34 ram Exp $
 *
 *  Copyright (c) 1995, Raphael Manfredi
 *  
 *  You may redistribute only under the terms of the Artistic License,
 *  as specified in the README file that comes with the distribution.
 *
 * $Log: Storable.xs,v $
 * Revision 0.1  1995/09/29  20:19:34  ram
 * Baseline for first netwide alpha release.
 *
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "config.h"

/*#define DEBUGME /* Debug mode, turns assertions on as well */
/*#define DASSERT /* Assertion mode */

#ifdef DEBUGME
#ifndef DASSERT
#define DASSERT
#endif
#define TRACEME(x)	do { printf x; printf("\n"); } while (0)
#else
#define TRACEME(x)
#endif

#ifdef DASSERT
#define ASSERT(x,y)	do { if (!x) { printf y; printf("\n"); }} while (0)
#else
#define ASSERT(x,y)
#endif

/*
 * Type markers.
 */

#define C(x) ((char) (x))	/* For markers with dynamic retrieval handling */

#define SX_OBJECT	C(0)	/* Already stored object */
#define SX_SCALAR	C(1)	/* Scalar forthcoming (length, data) */
#define SX_ARRAY	C(2)	/* Array forthcominng (size, item list) */
#define SX_HASH		C(3)	/* Hash forthcoming (size, key/value pair list) */
#define SX_REF		C(4)	/* Reference to object forthcoming */
#define SX_UNDEF	C(5)	/* Undefined scalar */
#define SX_ERROR	C(6)	/* Error */
#define SX_ITEM		'i'		/* An array item introducer */
#define SX_IT_UNDEF	'I'		/* Undefined array item */
#define SX_KEY		'k'		/* An hash key introducer */
#define SX_VALUE	'v'		/* An hash value introducer */
#define SX_VL_UNDEF	'V'		/* Undefined hash value */

/*
 * Notification markers.
 */

#define SX_BLESS	'b'		/* Object is blessed, class name length <255 */
#define SX_LG_BLESS	'B'		/* Object is blessed, class name length >255 */
#define SX_STORED	'X'		/* End of object */

#define LG_BLESS	255		/* Large blessing classname length limit */

/*
 * At store time:
 * This hash table records the objects which have already been stored.
 * Those are referred to as SX_OBJECT in the file, and their "tag" (i.e.
 * their memory address) is used to identify them.
 *
 * At retrieve time:
 * This hash table records the objects which have already been retrieved,
 * as seen by the tag preceeding the object data themselves. The reference
 * to that retrieved object is kept in the table, and is returned when an
 * SX_OBJECT is found bearing that same tag.
 */
static HV *seen;			/* XXX multi-threading needs context */

/*
 * The following structure is used for hash table key retrieval. Since, when
 * retrieving objects, we'll be facing blessed hash references, it's best
 * to pre-allocate that buffer once and resize it as the need arises, never
 * freeing it (keys will be saved away someplace else anyway, so even large
 * keys are not enough a motivation to reclaim that space).
 */
static struct {
	char *arena;		/* Will hold hash key strings, resized as needed */
	STRLEN asiz;		/* Size of aforementionned buffer */
} keybuf;

#define kbuf	keybuf.arena
#define ksiz	keybuf.asiz
#define KBUFINIT() do {					\
	if (!kbuf) {						\
		TRACEME(("** allocating kbuf of 128 bytes")); \
		New(10003, kbuf, 128, char);	\
		ksiz = 128;						\
	}} while (0)
#define KBUFCHK(x) do {			\
	if (x >= ksiz) {			\
		TRACEME(("** extending kbuf to %d bytes", x+1)); \
		Renew(kbuf, x+1, char);	\
		ksiz = x+1;				\
	}} while (0)

#define svis_REF	0
#define svis_SCALAR	1
#define svis_ARRAY	2
#define svis_HASH	3
#define svis_OTHER	4

static char *magicstr = "perl-store";	/* Used as a magic number */

/*
 * Useful store shortcuts...
 */
#define PUTMARK(x) do {				\
	if (fputc(x, f) == EOF)	\
		return -1;					\
	} while (0)

#define WLEN(x)	do {						\
	if (fwrite(&x, sizeof(x), 1, f) != 1)	\
		return -1;							\
	} while (0)

#define WRITE(x,y) do {				\
	if (fwrite(x, y, 1, f) != 1)	\
		return -1;					\
	} while (0)

/*
 * Useful retrieve shortcuts...
 */
#define GETMARK(x) do {				\
	if ((x = fgetc(f)) == EOF)		\
		return (SV *) 0;			\
	} while (0)

#define RLEN(x)	do {						\
	if (fread(&x, sizeof(x), 1, f) != 1)	\
		return (SV *) 0;					\
	} while (0)

#define READ(x,y) do {			\
	if (fread(x, y, 1, f) != 1)	\
		return (SV *) 0;		\
	} while (0)

#define SAFEREAD(x,y,z) do { 		\
	if (fread(x, y, 1, f) != 1) {	\
		sv_free(z);					\
		return (SV *) 0;			\
	}} while (0)

#define SEEN(x,y) do {			\
	if (!y)						\
		return (SV *) 0;		\
	ASSERT(!hv_fetch(seen, (char *) &x, sizeof(x), FALSE),	\
		("*** ALREADY SEEN 0x%lx ***", (unsigned long) x));	\
	if (hv_store(seen, (char *) &x, sizeof(x), SvREFCNT_inc(y), 0) == 0) \
		return (SV *) 0;		\
	TRACEME(("seen(0x%lx) = 0x%lx (%d ref)", (unsigned long) x, \
		(unsigned long) y, SvREFCNT(y))); \
	} while (0)

static int store();
static SV *retrieve();

/*
 * store_ref
 *
 * Store a reference.
 * Layout is SX_REF <object>.
 */
static int store_ref(f, sv)
FILE *f;
SV *sv;
{
	TRACEME(("store_ref (0x%lx)", (unsigned long) sv));

	PUTMARK(SX_REF);
	sv = SvRV(sv);
	return store(f, sv);
}

/*
 * store_scalar
 *
 * Store a scalar.
 *
 * Layout is SX_SCALAR <length> <data> or SX_UNDEF.
 * The <data> section is omitted if <length> is 0.
 */
static int store_scalar(f, sv)
FILE *f;
SV *sv;
{
	char *pv;
	STRLEN len;

	TRACEME(("store_scalar (0x%lx)", (unsigned long) sv));

	if (sv == &sv_undef) {
		TRACEME(("undef"));
		PUTMARK(SX_UNDEF);
		return 0;
	}

	/*
	 * Always store the string representation of the scalar.
	 * Write SX_SCALAR, length, followed by the actual data.
	 */

	PUTMARK(SX_SCALAR);
	pv = SvPV(sv, len);
	WLEN(len);
	if (len)
		WRITE(pv, len);
	TRACEME(("ok (scalar 0x%lx, length = %d)", (unsigned long) sv, len));

	return 0;		/* Ok, no recursion on scalars */
}

/*
 * store_array
 *
 * Store an array.
 *
 * Layout is SX_ARRAY <size> followed by each item, in increading index order.
 * Each item is stored as SX_ITEM <object> or SX_IT_UNDEF for "holes".
 */
static int store_array(f, av)
FILE *f;
AV *av;
{
	SV **sav;
	I32 len = av_len(av) + 1;
	I32 i;
	int ret;

	TRACEME(("store_array (0x%lx)", (unsigned long) av));

	/* 
	 * Signal array by emitting SX_ARRAY, followed by the array length.
	 */

	PUTMARK(SX_ARRAY);
	WLEN(len);
	TRACEME(("size = %d", len));

	/*
	 * Now store each item recursively.
	 */

	for (i = 0; i < len; i++) {
		sav = av_fetch(av, i, 0);
		if (!sav) {
			TRACEME(("(#%d) undef item", i));
			PUTMARK(SX_IT_UNDEF);
			continue;
		}
		TRACEME(("(#%d) item", i));
		PUTMARK(SX_ITEM);
		if (ret = store(f, *sav))
			return ret;
	}

	TRACEME(("ok (array)"));

	return 0;
}

/*
 * store_hash
 *
 * Store an hash table.
 *
 * Layout is SX_HASH <size> followed by each key/value pair, in random order.
 * Values are stored as SX_VALUE <object> or SX_VL_UNDEF for "holes".
 * Keys are stored as SX_KEY <length> <data>, the <data> section being omitted
 * if length is 0.
 */
static int store_hash(f, hv)
FILE *f;
HV *hv;
{
	I32 len = HvKEYS(hv);
	I32 i;
	int ret = 0;
	I32 riter;
	HE *eiter;

	TRACEME(("store_hash (0x%lx)", (unsigned long) hv));

	/* 
	 * Signal hash by emitting SX_HASH, followed by the table length.
	 */

	PUTMARK(SX_HASH);
	WLEN(len);
	TRACEME(("size = %d", len));

	/*
	 * Save possible iteration state via each() on that table.
	 */

	riter = HvRITER(hv);
	eiter = HvEITER(hv);
	hv_iterinit(hv);

	/*
	 * Now store each item recursively.
	 */

	for (i = 0; i < len; i++) {
		char *key;
		I32 len;
		SV *val = hv_iternextsv(hv, &key, &len);
		if (val == 0)
			return 1;		/* Internal error, not I/O error */

		/*
		 * Store value first, if defined.
		 */

		if (val == &sv_undef) {
			TRACEME(("undef value"));
			PUTMARK(SX_VL_UNDEF);
		} else {
			TRACEME(("(#%d) value 0x%lx", i, (unsigned long) val));
			PUTMARK(SX_VALUE);
			if (ret = store(f, val))
				goto out;
		}

		/*
		 * Write key string.
		 * Keys are written after values to make sure retrieval
		 * can be optimal in terms of memory usage, where keys are
		 * read into a fixed unique buffer called kbuf.
		 * See retrieve_hash() for details.
		 */

		TRACEME(("(#%d) key '%s'", i, key));
		PUTMARK(SX_KEY);
		WLEN(len);
		if (len)
			WRITE(key, len);
	}

	TRACEME(("ok (hash 0x%lx)", (unsigned long) hv));

out:
	HvRITER(hv) = riter;		/* Restore hash iterator state */
	HvEITER(hv) = eiter;

	return ret;
}

/*
 * store_other
 *
 * We don't know how to store the item we reached, so return an error condition.
 * (it's probably a GLOB, some CODE reference, etc...)
 */
static int store_other(f, sv)
FILE *f;
SV *sv;
{
	TRACEME(("store_other"));
	croak("Can't store %s items", sv_reftype(sv, FALSE));
}

/*
 * Dynamic dispatching table for SV store.
 */
static int (*sv_store[])() = {
	store_ref,		/* svis_REF */
	store_scalar,	/* svis_SCALAR */
	store_array,	/* svis_ARRAY */
	store_hash,		/* svis_HASH */
	store_other,	/* svis_OTHER */
};

#define SV_STORE(x)	(*sv_store[x])

/*
 * sv_type
 *
 * WARNING: partially duplicates Perl's sv_reftype for speed.
 *
 * Returns the type of the SV, identified by an integer. That integer
 * may then be used to index the dynamic routine dispatch table.
 */
static int sv_type(sv)
SV *sv;
{
	switch (SvTYPE(sv)) {
	case SVt_NULL:
	case SVt_IV:
	case SVt_NV:
	case SVt_RV:
	case SVt_PV:
	case SVt_PVIV:
	case SVt_PVNV:
	case SVt_PVMG:
	case SVt_PVBM:
		if (SvROK(sv))
			return svis_REF;
		else
			return svis_SCALAR;
	case SVt_PVAV:
		return svis_ARRAY;
	case SVt_PVHV:
		return svis_HASH;
	default:
		return svis_OTHER;
	}
}

/*
 * store
 *
 * Recursively store objects pointed to by the sv to the specified file.
 *
 * Layout is <addr-tag> <content> SX_STORED or <addr-tag> SX_OBJECT if we
 * reach an already stored object (one for which storage has started--
 * it may not be over if we have a self-referenced structure). This data set
 * forms a stored <object>.
 */
static int store(f, sv)
FILE *f;
SV *sv;
{
	SV **svh;
	int ret;
	int type;
	SV *rv;

	TRACEME(("store (0x%lx)", (unsigned long) sv));

	/*
	 * If object has already been stored, do not duplicate data.
	 * Simply emit the SX_OBJECT marker followed by its address data.
	 */

	svh = hv_fetch(seen, (char *) &sv, sizeof(sv), FALSE);
	if (svh) {
		TRACEME(("object 0x%lx seen", (unsigned long) sv));
		WRITE(&sv, sizeof(sv));
		PUTMARK(SX_OBJECT);
		return 0;
	}

	/*
	 * Record the address as being stored, before recursing...
	 */

	if (hv_store(seen, (char *) &sv, sizeof(sv), &sv_undef, 0) == 0)
		return -1;
	TRACEME(("recorded 0x%lx...", (unsigned long) sv));

	/*
	 * Call the proper routine to store this SV.
	 * Abort immediately if we get a non-zero status back.
	 */

	TRACEME(("storing..."));
	WRITE(&sv, sizeof(sv));
	type = sv_type(sv);

	if (ret = SV_STORE(type)(f, sv))
		return ret;

	/*
	 * If reference is blessed, notify the blessing now.
	 *
	 * Since the storable mechanism is going to make usage of lots
	 * of blessed objects (!), we're trying to optimize the cost
	 * by having two separate blessing notifications:
	 *    SX_BLESS <char-len> <class> for short classnames (<255 chars)
	 *    SX_LG_BLESS <int-len> <class> for larger classnames.
	 */

	if (type == svis_REF && (rv = SvRV(sv)) && SvOBJECT(rv)) {
		char *class = HvNAME(SvSTASH(rv));
		I32 len = strlen(class);
		unsigned char clen;
		TRACEME(("blessing 0x%lx in %s", (unsigned long) sv, class));
		if (len <= LG_BLESS) {
			PUTMARK(SX_BLESS);
			clen = (unsigned char) len;
			PUTMARK(clen);
		} else {
			PUTMARK(SX_LG_BLESS);
			WLEN(len);
		}
		WRITE(class, len);		/* Final \0 is omitted */
	}

	/*
	 * Finally, notify the original object's address so that we
	 * may resolve SX_OBJECT at retrieval time.
	 */

	PUTMARK(SX_STORED);
	TRACEME(("ok (store 0x%lx)", (unsigned long) sv));

	return 0;	/* Done, with success */
}

/*
 * magic_write
 *
 * Write magic number and system information into the file.
 * Layout is <magic> <len> <byteorder> <sizeof int> <sizeof long> <sizeof ptr>
 * where <len> is the length of the byteorder hexa string. All size and lenghts
 * are written as single characters here.
 */
static int magic_write(f)
FILE *f;
{
	char buf[256];	/* Enough room for 256 hexa digits */
	unsigned char c;

	TRACEME(("magic_write"));

	WRITE(magicstr, strlen(magicstr));	/* Don't write final \0 */
	sprintf(buf, "%lx", (unsigned long) BYTEORDER);
	c = (unsigned char) strlen(buf);
	PUTMARK(c);
	WRITE(buf, (unsigned int) c);		/* Don't write final \0 */
	PUTMARK((unsigned char) sizeof(int));
	PUTMARK((unsigned char) sizeof(long));
	PUTMARK((unsigned char) sizeof(char *));

	TRACEME(("ok (magic_write byteorder = 0x%lx [%d], I%d L%d P%d)",
		(unsigned long) BYTEORDER, (int) c,
		sizeof(int), sizeof(long), sizeof(char *)));

	return 0;
}

/*
 * pstore
 *
 * Store the transitive data closure of given object to disk.
 * Returns 0 on error, a true value otherwise.
 */
int pstore(f, sv)
FILE *f;
SV *sv;
{
	int status;

	TRACEME(("pstore"));

	if (-1 == magic_write(f))		/* Emit magic number and system info */
		return 0;					/* Error */

	/*
	 * Ensure sv is actually a reference. From perl, we called something
	 * like:
	 *       pstore(FILE, \@array);
	 * so we must get the scalar value behing that reference.
	 */

	if (!SvROK(sv))
		croak("Not a reference");
	sv = SvRV(sv);

	seen = newHV();			/* Table where seen objects are stored */
	status = store(f, sv);	/* Recursively store object */
	hv_undef(seen);			/* Free seen object table */

	TRACEME(("pstore returns %d", status));

	return status == 0;
}

/*
 * retrieve_ref
 *
 * Retrieve reference to some other scalar.
 * Layout is SX_REF <object>, with SX_REF already read.
 */
static SV *retrieve_ref(f, addr)
FILE *f;
char *addr;
{
	SV *rv;
	SV *sv;

	TRACEME(("retrieve_ref (0x%lx)", (unsigned long) addr));

	/*
	 * We need to create the SV that holds the reference to the yet-to-retrieve
	 * object now, so that we may record the address in the seen table.
	 * Otherwise, if the object to retrieve references us, we won't be able
	 * to resolve the SX_OBJECT we'll see at that point! Hence we cannot
	 * do the retrieve first and use rv = newRV(sv) since it will be too late
	 * for SEEN() recording.
	 */

	rv = NEWSV(10002, 0);
	SEEN(addr, rv);			/* Will return if rv is null */
	sv = retrieve(f);		/* Retrieve <object> */
	if (!sv)
		return (SV *) 0;	/* Failed */

	/*
	 * WARNING: breaks RV encapsulation.
	 *
	 * Now for the tricky part. We have to upgrade our existing SV, so that
	 * it is now an RV on rv... Again, we cheat by duplicating the code
	 * held in newSVrv(), since we already got our SV from retrieve().
	 */

	sv_upgrade(rv, SVt_RV);
	SvRV(rv) = SvREFCNT_inc(sv);	/* $rv = \$sv */
	SvROK_on(rv);

	TRACEME(("ok (retrieve_ref at 0x%lx)", (unsigned long) rv));

	return rv;
}

/*
 * retrieve_scalar
 *
 * Retrieve defined scalar.
 *
 * Layout is SX_SCALAR <length> <data>, with SX_SCALAR already read.
 * The <data> section is omitted if <length> is 0.
 */
static SV *retrieve_scalar(f, addr)
FILE *f;
char *addr;
{
	STRLEN len;
	SV *sv;
	char *buf;

	TRACEME(("retrieve_scalar (0x%lx)", (unsigned long) addr));

	/*
	 * Allocate an empty scalar of the suitable length.
	 */

	RLEN(len);
	sv = NEWSV(10001, len);
	SEEN(addr, sv);			/* Associate this new scalar with tag "addr" */

	if (len == 0) {
		TRACEME(("ok (retrieve_scalar empty at 0x%lx)", (unsigned long) sv));
		return sv;
	}

	/*
	 * WARNING: duplicates parts of sv_setpv and breaks SV data encapsulation.
	 *
	 * Now, for efficiency reasons, read data directly inside the SV buffer,
	 * and perform the SV final settings directly by duplicating the final
	 * work done by sv_setpv. Since we're going to allocate lots of scalars
	 * this way, it's worth the hassle and risk.
	 */

	SAFEREAD(SvPVX(sv), len, sv);
	SvCUR_set(sv, len);				/* Record C string length */
	*SvEND(sv) = '\0';				/* Ensure it's null terminated anyway */
	(void) SvPOK_only(sv);			/* Validate string pointer */
	SvTAINT(sv);					/* External data cannot be trusted */

	TRACEME(("scalar len %d '%s'", len, SvPVX(sv)));
	TRACEME(("ok (retrieve_scalar at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_undef
 *
 * Return the undefined value.
 */
static SV *retrieve_undef()
{
	TRACEME(("retrieve_undef"));
	return &sv_undef;
}

/*
 * retrieve_other
 *
 * Return an error via croak, since it is not possible that we get here
 * under normal conditions, when facing a file produced via pstore().
 */
static SV *retrieve_other()
{
	croak("Corrupted perl storable file");
}

/*
 * retrieve_array
 *
 * Retrieve a whole array.
 * Layout is SX_ARRAY <size> followed by each item, in increading index order.
 * Each item is stored as SX_ITEM <object> or SX_IT_UNDEF for "holes".
 *
 * When we come here, SX_ARRAY has been read already.
 */
static SV *retrieve_array(f, addr)
FILE *f;
char *addr;
{
	I32 len;
	I32 i;
	AV *av;
	SV *sv;
	int c;

	TRACEME(("retrieve_array (0x%lx)", (unsigned long) addr));

	/*
	 * Read length, and allocate array, then pre-extend it.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	av = newAV();
	SEEN(addr, av);				/* Will return if array not allocated nicely */
	if (len)
		av_extend(av, len);
	if (len == 0)
		return (SV *) av;		/* No data follow if array is empty */

	/*
	 * Now get each item in turn...
	 */

	for (i = 0; i < len; i++) {
		GETMARK(c);
		if (c == SX_IT_UNDEF) {
			TRACEME(("(#%d) undef item", i));
			continue;			/* av_extend() already filled us with undef */
		}
		if (c != SX_ITEM)
			(void) retrieve_other();	/* Will croak out */
		TRACEME(("(#%d) item", i));
		sv = retrieve(f);				/* Retrieve item */
		if (!sv)
			return (SV *) 0;
		if (av_store(av, i, sv) == 0)
			return (SV *) 0;
	}

	TRACEME(("ok (retrieve_array at 0x%lx)", (unsigned long) av));

	return (SV *) av;
}

/*
 * retrieve_hash
 *
 * Retrieve a whole hash table.
 * Layout is SX_HASH <size> followed by each key/value pair, in random order.
 * Keys are stored as SX_KEY <length> <data>, the <data> section being omitted
 * if length is 0.
 * Values are stored as SX_VALUE <object> or SX_VL_UNDEF for "holes".
 *
 * When we come here, SX_HASH has been read already.
 */
static SV *retrieve_hash(f, addr)
FILE *f;
char *addr;
{
	I32 len;
	I32 size;
	I32 i;
	HV *hv;
	SV *sv;
	int c;

	TRACEME(("retrieve_hash (0x%lx)", (unsigned long) addr));

	/*
	 * Read length, allocate table.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	hv = newHV();
	SEEN(addr, hv);			/* Will return if table not allocated properly */
	if (len == 0)
		return (SV *) hv;	/* No data follow if table empty */

	/*
	 * Now get each key/value pair in turn...
	 */

	for (i = 0; i < len; i++) {
		/*
		 * Get value first.
		 */

		GETMARK(c);
		if (c == SX_VL_UNDEF) {
			TRACEME(("(#%d) undef value", i));
			sv = &sv_undef;
		} else if (c == SX_VALUE) {
			TRACEME(("(#%d) value", i));
			sv = retrieve(f);
			if (!sv)
				return (SV *) 0;
		} else
			(void) retrieve_other();	/* Will croak out */

		/*
		 * Get key.
		 * Since we're reading into kbuf, we must ensure we're not
		 * recursing between the read and the hv_store() where it's used.
		 * Hence the key comes after the value.
		 */

		GETMARK(c);
		if (c != SX_KEY)
			(void) retrieve_other();	/* Will croak out */
		RLEN(size);						/* Get key size */
		KBUFCHK(size);					/* Grow hash key read pool if needed */
		if (size)
			READ(kbuf, size);
		kbuf[size] = '\0';				/* Mark string end, just in case */
		TRACEME(("(#%d) key '%s'", i, kbuf));

		/*
		 * Enter key/value pair into hash table.
		 */

		if (hv_store(hv, kbuf, (U32) size, sv, 0) == 0)
			return (SV *) 0;
	}

	TRACEME(("ok (retrieve_hash at 0x%lx)", (unsigned long) hv));

	return (SV *) hv;
}

/*
 * Dynamic dispatching table for SV retrive.
 */

static SV *(*sv_retrieve[])() = {
	0,					/* SX_OBJECT -- entry unused dynamically */
	retrieve_scalar,	/* SX_SCALAR */
	retrieve_array,		/* SX_ARRAY */
	retrieve_hash,		/* SX_HASH */
	retrieve_ref,		/* SX_REF */
	retrieve_undef,		/* SX_UNDEF */
	retrieve_other,		/* SX_ERROR */
};

#define RETRIEVE(x)	(*sv_retrieve[(x) >= SX_ERROR ? SX_ERROR : (x)])

/*
 * magic_check
 *
 * Make sure the stored data we're trying to retrieve has been produced
 * on an ILP compatible system with the same byteorder. It croaks out in
 * case an error is detected. [ILP = integer-long-pointer sizes]
 * Returns null if error is detected, &sv_undef otherwise.
 */
static SV *magic_check(f)
FILE *f;
{
	char buf[256];
	char byteorder[256];
	STRLEN len = strlen(magicstr);
	int c;

	READ(buf, len);		/* Not null-terminated */
	buf[len] = '\0';	/* Is now */

	if (strcmp(buf, magicstr))
		croak("File is not a perl storable");

	sprintf(byteorder, "%lx", (unsigned long) BYTEORDER);
	GETMARK(c);
	READ(buf, c);	/* Not null-terminated */
	buf[c] = '\0';	/* Is now */

	if (strcmp(buf, byteorder))
		croak("Byte order is not compatible");
	
	GETMARK(c);		/* sizeof(int) */
	if ((int) c != sizeof(int))
		croak("Integer size is not compatible");

	GETMARK(c);		/* sizeof(long) */
	if ((int) c != sizeof(long))
		croak("Long integer size is not compatible");

	GETMARK(c);		/* sizeof(char *) */
	if ((int) c != sizeof(char *))
		croak("Pointer integer size is not compatible");

	return &sv_undef;	/* OK */
}

/*
 * retrieve
 *
 * Recursively retrieve objects from the specified file and return their
 * root SV (which may be an AV or an HV for what we care).
 * Returns null if there is a problem.
 */
static SV *retrieve(f)
FILE *f;
{
	char *addr;
	int type;
	SV **svh;
	SV *sv;

	TRACEME(("retrieve"));

	/*
	 * Grab address tag which identifies the object, followed by the object
	 * type. If it's an SX_OBJECT, then we're dealing with an object we
	 * should have already retrieved. Otherwise, we've got a new one....
	 */

	READ(&addr, sizeof(char *));
	GETMARK(type);

	TRACEME(("retrieve addr = 0x%lx, type = %d", (unsigned long) addr, type));

	if (type == SX_OBJECT) {
		svh = hv_fetch(seen, (char *) &addr, sizeof(addr), FALSE);
		if (!svh)
			croak("Object 0x%lx should have been retrieved already",
				(unsigned long) addr, type);
		TRACEME(("already retrieved at 0x%lx", (unsigned long) *svh));
		return *svh;	/* The SV pointer where that object was retrieved */
	}

	/*
	 * Okay, first time through for this one.
	 */

	sv = RETRIEVE(type)(f, addr);
	if (!sv)
		return (SV *) 0;			/* Failed */

	/*
	 * Final notifications, ended by SX_STORED may now follow.
	 * Currently, the only pertinent notification to apply on the
	 * freshly retrieved object is either:
	 *    SX_BLESS <char-len> <classname> for short classnames.
	 *    SX_LG_BLESS <int-len> <classname> for larger one (rare!).
	 * Class name is then read into the key buffer pool used by
	 * hash table key retrieval.
	 */

	while ((type = fgetc(f)) != SX_STORED) {
		I32 len;
		HV *stash;
		switch (type) {
		case SX_BLESS:
			GETMARK(len);			/* Length coded on a single char */
			break;
		case SX_LG_BLESS:			/* Length coded on a regular integer */
			RLEN(len);
			break;
		case EOF:
		default:
			return (SV *) 0;		/* Failed */
		}
		KBUFCHK(len);				/* Grow buffer as necessary */
		if (len)
			READ(kbuf, len);
		kbuf[len] = '\0';			/* Mark string end */
		TRACEME(("blessing 0x%lx in %s", (unsigned long) sv, kbuf));
		stash = gv_stashpv(kbuf, TRUE);
		(void) sv_bless(sv, stash);
	}

	TRACEME(("ok (retrieved 0x%lx, %d ref, %s)", (unsigned long) sv,
		SvREFCNT(sv), sv_reftype(sv, FALSE)));

	return sv;	/* Ok */
}

/*
 * pretrieve
 *
 * Retrieve data held in file and return the root object.
 */
SV *pretrieve(f)
FILE *f;
{
	SV *sv;

	TRACEME(("pretrieve"));
	KBUFINIT();			 	/* Allocate hash key reading pool once */

	/*
	 * Magic number verifications.
	 */

	if (!magic_check(f))
		croak("Magic number checking on perl storable failed");

	seen = newHV();			/* Table where retrieved objects are kept */
	sv = retrieve(f);		/* Recursively retrieve object, get root SV  */
	hv_undef(seen);			/* Free retrieved object table */

	TRACEME(("retrieve got %s(0x%lx)",
		sv_reftype(sv, FALSE), (unsigned long) sv));

	if (!sv)
		return &sv_undef;	/* Something went wrong, return undef */

	/*
	 * Build a reference to the SV returned by pretrieve even if it is
	 * already one and not a scalar, for consistency reasons.
	 */

	return newRV(sv);
}

MODULE = Storable	PACKAGE = Storable

int
pstore(f,obj)
FILE *	f
SV *	obj

SV *
pretrieve(f)
FILE *	f

