/*
 * Store and retrieve mechanism.
 */

/*
 * $Id: Storable.xs,v 0.5.1.3 1998/04/08 11:13:35 ram Exp $
 *
 *  Copyright (c) 1995-1997, Raphael Manfredi
 *  
 *  You may redistribute only under the terms of the Artistic License,
 *  as specified in the README file that comes with the distribution.
 *
 * $Log: Storable.xs,v $
 * Revision 0.5.1.3  1998/04/08  11:13:35  ram
 * patch5: wrote sizeof(SV *) instead of sizeof(I32) when portable
 *
 * Revision 0.5.1.2  1998/03/25  13:50:50  ram
 * patch4: cannot use SV addresses as tag when using nstore() on LP64
 *
 * Revision 0.5.1.1  1997/11/05  09:51:35  ram
 * patch1: fix memory leaks on seen hash table and returned SV refs
 * patch1: did not work properly when tainting enabled
 * patch1: fixed "Allocation too large" messages in freeze/thaw
 *
 * Revision 0.5  1997/06/10  16:38:38  ram
 * Baseline for fifth alpha release.
 *
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/*#define DEBUGME /* Debug mode, turns assertions on as well */
/*#define DASSERT /* Assertion mode */

/*
 * Pre PerlIO time when none of USE_PERLIO and PERLIO_IS_STDIO is defined
 * Provide them with the necessary defines so they can build with pre-5.004.
 */
#ifndef USE_PERLIO
#ifndef PERLIO_IS_STDIO
#define PerlIO FILE
#define PerlIO_getc(x) getc(x)
#define PerlIO_putc(f,x) putc(x,f)
#define PerlIO_read(x,y,z) fread(y,1,z,x)
#define PerlIO_write(x,y,z) fwrite(y,1,z,x)
#define PerlIO_stdoutf printf
#endif	/* PERLIO_IS_STDIO */
#endif	/* USE_PERLIO */

/*
 * Earlier versions of perl might be used, we can't assume they have the latest!
 */
#ifndef newRV_noinc
#define newRV_noinc(sv)		((Sv = newRV(sv)), --SvREFCNT(SvRV(Sv)), Sv)
#endif

#ifdef DEBUGME
#ifndef DASSERT
#define DASSERT
#endif
#define TRACEME(x)	do { PerlIO_stdoutf x; PerlIO_stdoutf("\n"); } while (0)
#else
#define TRACEME(x)
#endif

#ifdef DASSERT
#define ASSERT(x,y)	do { \
	if (!x) { PerlIO_stdoutf y; PerlIO_stdoutf("\n"); }} while (0)
#else
#define ASSERT(x,y)
#endif

/*
 * Type markers.
 */

#define C(x) ((char) (x))	/* For markers with dynamic retrieval handling */

#define SX_OBJECT	C(0)	/* Already stored object */
#define SX_LSCALAR	C(1)	/* Scalar (string) forthcoming (length, data) */
#define SX_ARRAY	C(2)	/* Array forthcominng (size, item list) */
#define SX_HASH		C(3)	/* Hash forthcoming (size, key/value pair list) */
#define SX_REF		C(4)	/* Reference to object forthcoming */
#define SX_UNDEF	C(5)	/* Undefined scalar */
#define SX_INTEGER	C(6)	/* Integer forthcoming */
#define SX_DOUBLE	C(7)	/* Double forthcoming */
#define SX_BYTE		C(8)	/* (signed) byte forthcoming */
#define SX_NETINT	C(9)	/* Integer in network order forthcoming */
#define SX_SCALAR	C(10)	/* Scalar (small) forthcoming (length, data) */
#define SX_ERROR	C(11)	/* Error */
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
#define LG_SCALAR	255		/* Large scalar length limit */

/*
 * The following structure is used for hash table key retrieval. Since, when
 * retrieving objects, we'll be facing blessed hash references, it's best
 * to pre-allocate that buffer once and resize it as the need arises, never
 * freeing it (keys will be saved away someplace else anyway, so even large
 * keys are not enough a motivation to reclaim that space).
 *
 * This structure is also used for memory store/retrieve operations which
 * happen in a fixed place before being malloc'ed elsewhere if persistency
 * is required. Hence the aptr pointer.
 */
struct extendable {
	char *arena;		/* Will hold hash key strings, resized as needed */
	STRLEN asiz;		/* Size of aforementionned buffer */
	char *aptr;			/* Arena pointer, for in-place read/write ops */
	char *aend;			/* First invalid address */
};

/*
 * At store time:
 * This hash table records the objects which have already been stored.
 * Those are referred to as SX_OBJECT in the file, and their "tag" (i.e.
 * an arbitrary sequence number) is used to identify them.
 *
 * At retrieve time:
 * This hash table records the objects which have already been retrieved,
 * as seen by the tag preceeding the object data themselves. The reference
 * to that retrieved object is kept in the table, and is returned when an
 * SX_OBJECT is found bearing that same tag.
 */

/*
 * The tag is a 32-bit integer, for portability, otherwise it is an address.
 * It is assumed a long is large enough to hold a pointer.
 */
typedef unsigned long stag_t;

/*
 * XXX multi-threading needs context for the following variables...
 */
static HV *seen;			/* which objects have been seen */
static I32 tagnum;			/* incremented at store time for each seen object */
static int netorder = 0;	/* true if network order used */
static int forgive_me = -1;	/* whether to be forgiving... */
struct extendable keybuf;	/* for hash key retrieval */
struct extendable membuf;	/* for memory store/retrieve operations */

/*
 * key buffer handling
 */
#define kbuf	keybuf.arena
#define ksiz	keybuf.asiz
#define KBUFINIT() do {					\
	if (!kbuf) {						\
		TRACEME(("** allocating kbuf of 128 bytes")); \
		New(10003, kbuf, 128, char);	\
		ksiz = 128;						\
	}									\
} while (0)
#define KBUFCHK(x) do {			\
	if (x >= ksiz) {			\
		TRACEME(("** extending kbuf to %d bytes", x+1)); \
		Renew(kbuf, x+1, char);	\
		ksiz = x+1;				\
	}							\
} while (0)

/*
 * memory buffer handling
 */
#define mbase	membuf.arena
#define msiz	membuf.asiz
#define mptr	membuf.aptr
#define mend	membuf.aend
#define MGROW	(1 << 13)
#define MMASK	(MGROW - 1)

#define round_mgrow(x)	\
	((unsigned long) (((unsigned long) (x) + MMASK) & ~MMASK))
#define trunc_int(x)	\
	((unsigned long) ((unsigned long) (x) & ~(sizeof(int)-1)))
#define int_aligned(x)	\
	((unsigned long) (x) == trunc_int(x))

#define MBUF_INIT(x) do {				\
	if (!mbase) {						\
		TRACEME(("** allocating mbase of %d bytes", MGROW)); \
		New(10003, mbase, MGROW, char);	\
		msiz = MGROW;					\
	}									\
	mptr = mbase;						\
	if (x)								\
		mend = mbase + x;				\
	else								\
		mend = mbase + msiz;			\
} while (0)

#define MBUF_SIZE()	(mptr - mbase)

/*
 * Use SvPOKp(), because SvPOK() fails on tainted scalars.
 * See store_scalar() for other usage of this workaround.
 */
#define MBUF_LOAD(v) do {				\
	if (!SvPOK(v))						\
		croak("Not a scalar string");	\
	mptr = mbase = SvPV(v, msiz);		\
	mend = mbase + msiz;				\
} while (0)

#define MBUF_XTEND(x) do {			\
	int nsz = (int) round_mgrow((x)+msiz);	\
	int offset = mptr - mbase;		\
	TRACEME(("** extending mbase to %d bytes", nsz));	\
	Renew(mbase, nsz, char);		\
	msiz = nsz;						\
	mptr = mbase + offset;			\
	mend = mbase + nsz;				\
} while (0)

#define MBUF_CHK(x) do {			\
	if ((mptr + (x)) > mend)		\
		MBUF_XTEND(x);				\
} while (0)

#define MBUF_GETC(x) do {			\
	if (mptr < mend)				\
		x = (int) (unsigned char) *mptr++;	\
	else							\
		return (SV *) 0;			\
} while (0)

#define MBUF_GETINT(x) do {				\
	if ((mptr + sizeof(int)) <= mend) {	\
		if (int_aligned(mptr))			\
			x = *(int *) mptr;			\
		else							\
			memcpy(&x, mptr, sizeof(int));	\
		mptr += sizeof(int);			\
	} else								\
		return (SV *) 0;				\
} while (0)

#define MBUF_READ(x,s) do {			\
	if ((mptr + (s)) <= mend) {		\
		memcpy(x, mptr, s);			\
		mptr += s;					\
	} else							\
		return (SV *) 0;			\
} while (0)

#define MBUF_SAFEREAD(x,s,z) do {	\
	if ((mptr + (s)) <= mend) {		\
		memcpy(x, mptr, s);			\
		mptr += s;					\
	} else {						\
		sv_free(z);					\
		return (SV *) 0;			\
	}								\
} while (0)

#define MBUF_PUTC(c) do {			\
	if (mptr < mend)				\
		*mptr++ = (char) c;			\
	else {							\
		MBUF_XTEND(1);				\
		*mptr++ = (char) c;			\
	}								\
} while (0)

#define MBUF_PUTINT(i) do {			\
	MBUF_CHK(sizeof(int));			\
	if (int_aligned(mptr))			\
		*(int *) mptr = i;			\
	else							\
		memcpy(mptr, &i, sizeof(int));	\
	mptr += sizeof(int);			\
} while (0)

#define MBUF_WRITE(x,s) do {		\
	MBUF_CHK(s);					\
	memcpy(mptr, x, s);				\
	mptr += s;						\
} while (0)


#define mbuf	membuf.arena
#define msiz	membuf.asiz

#define svis_REF	0
#define svis_SCALAR	1
#define svis_ARRAY	2
#define svis_HASH	3
#define svis_OTHER	4

static char *magicstr = "perl-store";	/* Used as a magic number */

/*
 * Useful store shortcuts...
 */
#define PUTMARK(x) do {					\
	if (!f)								\
		MBUF_PUTC(x);					\
	else if (PerlIO_putc(f, x) == EOF)	\
		return -1;						\
	} while (0)

#ifdef HAS_HTONL
#define WLEN(x)	do {				\
	if (netorder) {					\
		int y = (int) htonl(x);		\
		if (!f)						\
			MBUF_PUTINT(y);			\
		else if (PerlIO_write(f, &y, sizeof(y)) != sizeof(y))	\
			return -1;				\
	} else {						\
		if (!f)						\
			MBUF_PUTINT(x);			\
		else if (PerlIO_write(f, &x, sizeof(x)) != sizeof(x))	\
			return -1;				\
	}								\
} while (0)
#else
#define WLEN(x)	do {				\
	if (!f)							\
		MBUF_PUTINT(x);				\
	else if (PerlIO_write(f, &x, sizeof(x)) != sizeof(x))	\
		return -1;					\
	} while (0)
#endif

#define WRITE(x,y) do {						\
	if (!f)									\
		MBUF_WRITE(x,y);					\
	else if (PerlIO_write(f, x, y) != y)	\
		return -1;							\
	} while (0)

#define STORE_SCALAR(pv, len) do {		\
	if (len < LG_SCALAR) {				\
		unsigned char clen = (unsigned char) len;	\
		PUTMARK(SX_SCALAR);				\
		PUTMARK(clen);					\
		if (len)						\
			WRITE(pv, len);				\
	} else {							\
		PUTMARK(SX_LSCALAR);			\
		WLEN(len);						\
		WRITE(pv, len);					\
	}									\
} while (0)

/*
 * Useful retrieve shortcuts...
 */

#define GETCHAR() \
	(f ? PerlIO_getc(f) : (mptr >= mend ? EOF : (int) *mptr++))

#define GETMARK(x) do {						\
	if (!f)									\
		MBUF_GETC(x);						\
	else if ((x = PerlIO_getc(f)) == EOF)	\
		return (SV *) 0;					\
} while (0)

#ifdef HAS_NTOHL
#define RLEN(x)	do {					\
	if (!f)								\
		MBUF_GETINT(x);					\
	else if (PerlIO_read(f, &x, sizeof(x)) != sizeof(x))	\
		return (SV *) 0;				\
	if (netorder)						\
		x = (int) ntohl(x);				\
} while (0)
#else
#define RLEN(x)	do {					\
	if (!f)								\
		MBUF_GETINT(x);					\
	else if (PerlIO_read(f, &x, sizeof(x)) != sizeof(x))	\
		return (SV *) 0;				\
} while (0)
#endif

#define READ(x,y) do {					\
	if (!f)								\
		MBUF_READ(x, y);				\
	else if (PerlIO_read(f, x, y) != y)	\
		return (SV *) 0;				\
} while (0)

#define SAFEREAD(x,y,z) do { 				\
	if (!f)									\
		MBUF_SAFEREAD(x,y,z);				\
	else if (PerlIO_read(f, x, y) != y)	 {	\
		sv_free(z);							\
		return (SV *) 0;					\
	}										\
} while (0)

/*
 * This macro is used at retrieve time, to remember where object 'y', bearing a
 * given tag 'z', has been retrieve. Next time we see an SX_OBJECT marker,
 * we'll therefore know where it has been retrieved and will be able to
 * share the same reference, as in the original stored memory image.
 */
#define SEEN(z,y) do {						\
	if (!y)									\
		return (SV *) 0;					\
	ASSERT(!hv_fetch(seen, (char *) &z, sizeof(z), FALSE),	\
		("*** ALREADY SEEN object #%d ***", z));	\
	if (hv_store(seen, (char *) &z, sizeof(z), SvREFCNT_inc(y), 0) == 0) \
		return (SV *) 0;					\
	TRACEME(("seen(#%d) = 0x%lx (refcnt=%d)", z, \
		(unsigned long) y, SvREFCNT(y)-1)); \
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
PerlIO *f;
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
 * Layout is SX_LSCALAR <length> <data>, SX_SCALAR <lenght> <data> or SX_UNDEF.
 * The <data> section is omitted if <length> is 0.
 *
 * If integer or double, the layout is SX_INTEGER <data> or SX_DOUBLE <data>.
 * Small integers (within [-127, +127]) are stored as SX_BYTE <byte>.
 */
static int store_scalar(f, sv)
PerlIO *f;
SV *sv;
{
	IV iv;
	char *pv;
	STRLEN len;

	TRACEME(("store_scalar (0x%lx)", (unsigned long) sv));

	if (!SvOK(sv)) {
		TRACEME(("undef"));
		PUTMARK(SX_UNDEF);
		return 0;
	}

	/*
	 * Always store the string representation of a scalar if it exists.
	 * Write SX_SCALAR, length, followed by the actual data.
	 *
	 * Otherwise, write an SX_BYTE, SX_INTEGER or an SX_DOUBLE as
	 * appropriate, followed by the actual (binary) data. A double
	 * is written as a string if network order, for portability.
	 *
	 * NOTE: instead of using SvNOK(sv), we test for SvNOKp(sv).
	 * The reason is that when the scalar value is tainted, the SvNOK(sv)
	 * value is false.
	 */

	if (SvNOKp(sv)) {			/* Double */
		double nv = SvNV(sv);

		/*
		 * Watch for number being an integer in disguise.
		 */
		if (nv == (double) (iv = I_V(nv))) {
			TRACEME(("double %lf is actually integer %ld", nv, iv));
			goto integer;		/* Share code below */
		}

		if (netorder) {
			TRACEME(("double %lf stored as string", nv));
			pv = SvPV(sv, len);
			goto string;		/* Share code below */
		}

		PUTMARK(SX_DOUBLE);
		WRITE(&nv, sizeof(nv));

		TRACEME(("ok (double 0x%lx, value = %lf)", (unsigned long) sv, nv));

	} else if (SvIOKp(sv)) {		/* Integer */
		iv = SvIV(sv);

		/*
		 * Will come here from above with iv set if double is an integer.
		 */
	integer:

		/*
		 * Optimize small integers into a single byte, otherwise store as
		 * a real integer (converted into network order if they asked).
		 */

		if (iv >= -128 && iv <= 127) {
			unsigned char siv = (unsigned char) (iv + 128);	/* [0,255] */
			PUTMARK(SX_BYTE);
			PUTMARK(siv);
			TRACEME(("small integer stored as %d", siv));
		} else if (netorder) {
			int niv;
#ifdef HAS_HTONL
			niv = (int) htonl(iv);
			TRACEME(("using network order"));
#else
			niv = (int) iv;
			TRACEME(("as-is for network order"));
#endif
			PUTMARK(SX_NETINT);
			WRITE(&niv, sizeof(niv));
		} else {
			PUTMARK(SX_INTEGER);
			WRITE(&iv, sizeof(iv));
		}

		TRACEME(("ok (integer 0x%lx, value = %d)", (unsigned long) sv, iv));

	} else if (SvPOKp(sv)) {	/* String */
		pv = SvPV(sv, len);

		/*
		 * Will come here from above with pv and len set if double & netorder.
		 */
	string:

		STORE_SCALAR(pv, len);
		TRACEME(("ok (scalar 0x%lx '%s', length = %d)",
			(unsigned long) sv, SvPVX(sv), len));

	} else
		croak("Can't determine type of %s(0x%lx)", sv_reftype(sv, FALSE),
			(unsigned long) sv);

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
PerlIO *f;
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
PerlIO *f;
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

		if (!SvOK(val)) {
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
 *
 * If they defined the `forgive_me' variable at the Perl level to some
 * true value, then don't croak, just warn, and store a placeholder string
 * instead.
 */
static int store_other(f, sv)
PerlIO *f;
SV *sv;
{
	STRLEN len;
	static char buf[80];

	TRACEME(("store_other"));

	/*
	 * Fetch the value from perl only once per store() operation.
	 */

	if (
		forgive_me == 0 ||
		(forgive_me < 0 && !(forgive_me =
			SvTRUE(perl_get_sv("Storable::forgive_me", TRUE)) ? 1 : 0))
	)
		croak("Can't store %s items", sv_reftype(sv, FALSE));

	warn("Can't store %s items", sv_reftype(sv, FALSE));

	/*
	 * Store placeholder string as a scalar instead...
	 */

	(void) sprintf(buf, "You lost %s(0x%lx)\0", sv_reftype(sv, FALSE),
		(unsigned long) sv);

	len = strlen(buf);
	STORE_SCALAR(buf, len);
	TRACEME(("ok (dummy \"%s\", length = %d)", buf, len));

	return 0;
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
		break;
	}

	return svis_OTHER;
}

/*
 * sv_is_object
 *
 * Checks whether a reference actually points to an object.
 */
static int sv_is_object(sv)
SV *sv;
{
	SV *rv;

	return sv_type(sv) == svis_REF && (rv = SvRV(sv)) && SvOBJECT(rv);
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
PerlIO *f;
SV *sv;
{
	SV **svh;
	int ret;
	int type;
	SV *rv;
	SV *tag;

	TRACEME(("store (0x%lx)", (unsigned long) sv));

	/*
	 * If object has already been stored, do not duplicate data.
	 * Simply emit the SX_OBJECT marker followed by its tag data.
	 *
	 * When using network order, the tag is an I32 value, otherwise it
	 * is simply the address of the SV, for speed.
	 */

	svh = hv_fetch(seen, (char *) &sv, sizeof(sv), FALSE);
	if (svh) {
		if (netorder) {
			I32 tagval = SvIV(*svh);
			TRACEME(("object 0x%lx seen as #%d.", (unsigned long) sv, tagval));
			WRITE(&tagval, sizeof(I32));
		} else {
			WRITE(&sv, sizeof(SV *));
			TRACEME(("object 0x%lx seen.", (unsigned long) sv));
		}
		PUTMARK(SX_OBJECT);
		return 0;
	}

	/*
	 * Allocate a new tag and associate it with the address of the sv being
	 * stored, before recursing... The allocated tag SV will have a refcount
	 * of 1 and will be reclaimed when the %seen table is disposed of.
	 *
	 * When not saving using network order, it is not necessary to map an
	 * address to a tag: we can use the address itself. Of course, when
	 * saving on an LP64 system, that will give us 64-bit tags, but that
	 * avoids the creation of all those IV, which saves us around 5-10% of
	 * store time -- it doesn't make any difference at retrieve time.
	 */

	tagnum++;
	tag = netorder ? newSViv(tagnum) : SvREFCNT_inc(&sv_undef);

	if (!hv_store(seen, (char *) &sv, sizeof(sv), tag, 0))
		return -1;
	TRACEME(("recorded 0x%lx as object #%d", (unsigned long) sv, tagnum));

	/*
	 * Call the proper routine to store this SV.
	 * Abort immediately if we get a non-zero status back.
	 */

	type = sv_type(sv);
	TRACEME(("storing 0x%lx #%d type=%d...", (unsigned long) sv, tagnum, type));
	if (netorder)
		WRITE(&tagnum, sizeof(tagnum));
	else
		WRITE(&sv, sizeof(sv));

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
 * Layout is <magic> <network> [<len> <byteorder> <sizeof int> <sizeof long>
 * <sizeof ptr>] where <len> is the length of the byteorder hexa string.
 * All size and lenghts are written as single characters here.
 *
 * Note that no byte ordering info is emitted when <network> is true, since
 * integers will be emitted in network order in that case.
 */
static int magic_write(f, use_network_order)
PerlIO *f;
int use_network_order;
{
	char buf[256];	/* Enough room for 256 hexa digits */
	unsigned char c;

	TRACEME(("magic_write"));

	if (f)
		WRITE(magicstr, strlen(magicstr));	/* Don't write final \0 */

	c = use_network_order ? '\01' : '\0';
	PUTMARK(c);

	if (use_network_order)
		return 0;						/* Don't bother with byte ordering */

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
 * do_store
 *
 * Common code for pstore() and net_pstore().
 */
static int do_store(f, sv, use_network_order)
PerlIO *f;
SV *sv;
int use_network_order;
{
	int status;

	netorder = use_network_order;	/* Global, not suited for multi-thread */
	forgive_me = -1;				/* Unknown fetched from perl if needed */
	tagnum = 0;						/* Reset tag numbers */

	if (-1 == magic_write(f, netorder))	/* Emit magic number and system info */
		return 0;						/* Error */

	/*
	 * Ensure sv is actually a reference. From perl, we called something
	 * like:
	 *       pstore(FILE, \@array);
	 * so we must get the scalar value behing that reference.
	 */

	if (!SvROK(sv))
		croak("Not a reference");

	TRACEME(("do_store root is %s an object",
		sv_is_object(sv) ? "really" : "not"));

	if (!sv_is_object(sv))	/* If not an object, they gave a ref */
		sv = SvRV(sv);		/* So follow it to know what to store */

	seen = newHV();			/* Table where seen objects are stored */
	status = store(f, sv);	/* Recursively store object */
	hv_undef(seen);			/* Free seen object table */
	sv_free((SV *) seen);	/* Free HV */

	TRACEME(("do_store returns %d", status));

	return status == 0;
}

/*
 * mbuf2sv
 *
 * Build a new SV out of the content of the internal memory buffer.
 */
static SV *mbuf2sv()
{
	return newSVpv(mbase, MBUF_SIZE());
}

/*
 * mstore
 *
 * Store the transitive data closure of given object to memory.
 * Returns undef on error, a scalar value containing the data otherwise.
 */
SV *mstore(sv)
SV *sv;
{
	TRACEME(("mstore"));
	MBUF_INIT(0);
	if (!do_store(0, sv, FALSE))		/* Not in network order */
		return &sv_undef;

	return mbuf2sv();
}

/*
 * net_mstore
 *
 * Same as mstore(), but network order is used for integers and doubles are
 * emitted as strings.
 */
SV *net_mstore(sv)
SV *sv;
{
	TRACEME(("net_mstore"));
	MBUF_INIT(0);
	if (!do_store(0, sv, TRUE))	/* Use network order */
		return &sv_undef;

	return mbuf2sv();
}

/*
 * pstore
 *
 * Store the transitive data closure of given object to disk.
 * Returns 0 on error, a true value otherwise.
 */
int pstore(f, sv)
PerlIO *f;
SV *sv;
{
	TRACEME(("pstore"));
	return do_store(f, sv, FALSE);	/* Not in network order */

}

/*
 * net_pstore
 *
 * Same as pstore(), but network order is used for integers and doubles are
 * emitted as strings.
 */
int net_pstore(f, sv)
PerlIO *f;
SV *sv;
{
	TRACEME(("net_pstore"));
	return do_store(f, sv, TRUE);			/* Use network order */
}

/*
 * retrieve_ref
 *
 * Retrieve reference to some other scalar.
 * Layout is SX_REF <object>, with SX_REF already read.
 */
static SV *retrieve_ref(f, tag)
PerlIO *f;
stag_t tag;
{
	SV *rv;
	SV *sv;

	TRACEME(("retrieve_ref (#%d)", tag));

	/*
	 * We need to create the SV that holds the reference to the yet-to-retrieve
	 * object now, so that we may record the address in the seen table.
	 * Otherwise, if the object to retrieve references us, we won't be able
	 * to resolve the SX_OBJECT we'll see at that point! Hence we cannot
	 * do the retrieve first and use rv = newRV(sv) since it will be too late
	 * for SEEN() recording.
	 */

	rv = NEWSV(10002, 0);
	SEEN(tag, rv);			/* Will return if rv is null */
	sv = retrieve(f);		/* Retrieve <object> */
	if (!sv)
		return (SV *) 0;	/* Failed */

	/*
	 * WARNING: breaks RV encapsulation.
	 *
	 * Now for the tricky part. We have to upgrade our existing SV, so that
	 * it is now an RV on sv... Again, we cheat by duplicating the code
	 * held in newSVrv(), since we already got our SV from retrieve().
	 *
	 * We don't say:
	 *
	 *		SvRV(rv) = SvREFCNT_inc(sv);
	 *
	 * here because the reference count we got from retrieve() above is
	 * already correct: if the object was retrieved from the file, then
	 * its reference count is one. Otherwise, if it was retrieved via
	 * an SX_OBJECT indication, a ref count increment was done.
	 */

	sv_upgrade(rv, SVt_RV);
	SvRV(rv) = sv;				/* $rv = \$sv */
	SvROK_on(rv);

	TRACEME(("ok (retrieve_ref at 0x%lx)", (unsigned long) rv));

	return rv;
}

/*
 * retrieve_lscalar
 *
 * Retrieve defined long (string) scalar.
 *
 * Layout is SX_LSCALAR <length> <data>, with SX_LSCALAR already read.
 * The scalar is "long" in that <length> is larger than LG_SCALAR so it
 * was not stored on a single byte.
 */
static SV *retrieve_lscalar(f, tag)
PerlIO *f;
stag_t tag;
{
	STRLEN len;
	SV *sv;

	RLEN(len);
	TRACEME(("retrieve_lscalar (#%d), len = %d", tag, len));

	/*
	 * Allocate an empty scalar of the suitable length.
	 */

	sv = NEWSV(10002, len);
	SEEN(tag, sv);			/* Associate this new scalar with tag "tag" */

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

	TRACEME(("large scalar len %d '%s'", len, SvPVX(sv)));
	TRACEME(("ok (retrieve_lscalar at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_scalar
 *
 * Retrieve defined short (string) scalar.
 *
 * Layout is SX_SCALAR <length> <data>, with SX_SCALAR already read.
 * The scalar is "short" so <length> is single byte. If it is 0, there
 * is no <data> section.
 */
static SV *retrieve_scalar(f, tag)
PerlIO *f;
stag_t tag;
{
	int len;
	SV *sv;

	GETMARK(len);
	TRACEME(("retrieve_scalar (#%d), len = %d", tag, len));

	/*
	 * Allocate an empty scalar of the suitable length.
	 */

	sv = NEWSV(10002, len);
	SEEN(tag, sv);			/* Associate this new scalar with tag "tag" */

	/*
	 * WARNING: duplicates parts of sv_setpv and breaks SV data encapsulation.
	 */

	if (len == 0) {
		/*
		 * newSV did not upgrade to SVt_PV so the scalar is undefined.
		 * To make it defined with an empty length, upgrade it now...
		 */
		sv_upgrade(sv, SVt_PV);
		SvGROW(sv, 1);
		*SvEND(sv) = '\0';			/* Ensure it's null terminated anyway */
		TRACEME(("ok (retrieve_scalar empty at 0x%lx)", (unsigned long) sv));
	} else {
		/*
		 * Now, for efficiency reasons, read data directly inside the SV buffer,
		 * and perform the SV final settings directly by duplicating the final
		 * work done by sv_setpv. Since we're going to allocate lots of scalars
		 * this way, it's worth the hassle and risk.
		 */
		SAFEREAD(SvPVX(sv), len, sv);
		SvCUR_set(sv, len);			/* Record C string length */
		*SvEND(sv) = '\0';			/* Ensure it's null terminated anyway */
		TRACEME(("small scalar len %d '%s'", len, SvPVX(sv)));
	}

	(void) SvPOK_only(sv);			/* Validate string pointer */
	SvTAINT(sv);					/* External data cannot be trusted */

	TRACEME(("ok (retrieve_scalar at 0x%lx)", (unsigned long) sv));
	return sv;
}

/*
 * retrieve_integer
 *
 * Retrieve defined integer.
 * Layout is SX_INTEGER <data>, whith SX_INTEGER already read.
 */
static SV *retrieve_integer(f, tag)
PerlIO *f;
stag_t tag;
{
	SV *sv;
	IV iv;

	TRACEME(("retrieve_integer (#%d)", tag));

	READ(&iv, sizeof(iv));
	sv = newSViv(iv);
	SEEN(tag, sv);			/* Associate this new scalar with tag "tag" */

	TRACEME(("integer %d", iv));
	TRACEME(("ok (retrieve_integer at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_netint
 *
 * Retrieve defined integer in network order.
 * Layout is SX_NETINT <data>, whith SX_NETINT already read.
 */
static SV *retrieve_netint(f, tag)
PerlIO *f;
stag_t tag;
{
	SV *sv;
	int iv;

	TRACEME(("retrieve_netint (#%d)", tag));

	READ(&iv, sizeof(iv));
#ifdef HAS_NTOHL
	sv = newSViv((int) ntohl(iv));
	TRACEME(("network integer %d", (int) ntohl(iv)));
#else
	sv = newSViv(iv);
	TRACEME(("network integer (as-is) %d", iv));
#endif
	SEEN(tag, sv);			/* Associate this new scalar with tag "tag" */

	TRACEME(("ok (retrieve_netint at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_double
 *
 * Retrieve defined double.
 * Layout is SX_DOUBLE <data>, whith SX_DOUBLE already read.
 */
static SV *retrieve_double(f, tag)
PerlIO *f;
stag_t tag;
{
	SV *sv;
	double nv;

	TRACEME(("retrieve_double (#%d)", tag));

	READ(&nv, sizeof(nv));
	sv = newSVnv(nv);
	SEEN(tag, sv);			/* Associate this new scalar with tag "tag" */

	TRACEME(("double %lf", nv));
	TRACEME(("ok (retrieve_double at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_byte
 *
 * Retrieve defined byte (small integer within the [-128, +127] range).
 * Layout is SX_DOUBLE <data>, whith SX_DOUBLE already read.
 */
static SV *retrieve_byte(f, tag)
PerlIO *f;
stag_t tag;
{
	SV *sv;
	int siv;

	TRACEME(("retrieve_byte (#%d)", tag));

	GETMARK(siv);
	TRACEME(("small integer read as %d", (unsigned char) siv));
	sv = newSViv((unsigned char) siv - 128);
	SEEN(tag, sv);			/* Associate this new scalar with tag "tag" */

	TRACEME(("byte %d", (unsigned char) siv - 128));
	TRACEME(("ok (retrieve_byte at 0x%lx)", (unsigned long) sv));

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
	return (SV *) 0;
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
static SV *retrieve_array(f, tag)
PerlIO *f;
stag_t tag;
{
	I32 len;
	I32 i;
	AV *av;
	SV *sv;
	int c;

	TRACEME(("retrieve_array (#%d)", tag));

	/*
	 * Read length, and allocate array, then pre-extend it.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	av = newAV();
	SEEN(tag, av);				/* Will return if array not allocated nicely */
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
static SV *retrieve_hash(f, tag)
PerlIO *f;
stag_t tag;
{
	I32 len;
	I32 size;
	I32 i;
	HV *hv;
	SV *sv;
	int c;
	static SV *sv_h_undef = (SV *) 0;		/* hv_store() bug */

	TRACEME(("retrieve_hash (#%d)", tag));

	/*
	 * Read length, allocate table.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	hv = newHV();
	SEEN(tag, hv);			/* Will return if table not allocated properly */
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
			/*
			 * Due to a bug in hv_store(), it's not possible to pass &sv_undef
			 * to hv_store() as a value, otherwise the associated key will
			 * not be creatable any more. -- RAM, 14/01/97
			 */
			if (!sv_h_undef)
				sv_h_undef = newSVsv(&sv_undef);
			sv = SvREFCNT_inc(sv_h_undef);
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
	retrieve_lscalar,	/* SX_LSCALAR */
	retrieve_array,		/* SX_ARRAY */
	retrieve_hash,		/* SX_HASH */
	retrieve_ref,		/* SX_REF */
	retrieve_undef,		/* SX_UNDEF */
	retrieve_integer,	/* SX_INTEGER */
	retrieve_double,	/* SX_DOUBLE */
	retrieve_byte,		/* SX_BYTE */
	retrieve_netint,	/* SX_NETINT */
	retrieve_scalar,	/* SX_SCALAR */
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
 *
 * Note that there's no byte ordering info emitted when network order was
 * used at store time.
 */
static SV *magic_check(f)
PerlIO *f;
{
	char buf[256];
	char byteorder[256];
	STRLEN len = strlen(magicstr);
	int c;
	int use_network_order;

	if (f) {
		READ(buf, len);		/* Not null-terminated */
		buf[len] = '\0';	/* Is now */

		if (strcmp(buf, magicstr))
			croak("File is not a perl storable");
	}

	GETMARK(use_network_order);
	if (netorder = use_network_order)
		return &sv_undef;		/* No byte ordering info */

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
PerlIO *f;
{
	stag_t tag;
	int type;
	SV **svh;
	SV *sv;

	TRACEME(("retrieve"));

	/*
	 * Grab address tag which identifies the object, followed by the object
	 * type. If it's an SX_OBJECT, then we're dealing with an object we
	 * should have already retrieved. Otherwise, we've got a new one....
	 */

	if (netorder) {
		I32 nettag;
		READ(&nettag, sizeof(I32));		/* Ordereded sequence of I32 */
		tag = (stag_t) nettag;
	} else
		READ(&tag, sizeof(stag_t));		/* Address of the SV at store time */
	GETMARK(type);

	TRACEME(("retrieve tag #%d, type = %d", tag, type));

	if (type == SX_OBJECT) {
		svh = hv_fetch(seen, (char *) &tag, sizeof(tag), FALSE);
		if (!svh)
			croak("Object #%d should have been retrieved already", tag);
		sv = *svh;
		TRACEME(("already retrieved at 0x%lx", (unsigned long) sv));
		SvREFCNT_inc(sv);	/* One more reference to this same sv */
		return sv;			/* The SV pointer where object was retrieved */
	}

	/*
	 * Okay, first time through for this one.
	 */

	sv = RETRIEVE(type)(f, tag);
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

	while ((type = GETCHAR()) != SX_STORED) {
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

	TRACEME(("ok (retrieved 0x%lx, refcnt=%d, %s)", (unsigned long) sv,
		SvREFCNT(sv) - 1, sv_reftype(sv, FALSE)));

	return sv;	/* Ok */
}

/*
 * do_retrieve
 *
 * Retrieve data held in file and return the root object.
 * Common routine for pretrieve and mretrieve.
 */
static SV *do_retrieve(f)
PerlIO *f;
{
	SV *sv;

	TRACEME(("do_retrieve"));
	KBUFINIT();			 	/* Allocate hash key reading pool once */

	/*
	 * Magic number verifications.
	 */

	if (!magic_check(f))
		croak("Magic number checking on perl storable failed");

	seen = newHV();			/* Table where retrieved objects are kept */
	sv = retrieve(f);		/* Recursively retrieve object, get root SV  */
	hv_undef(seen);			/* Free retrieved object table */
	sv_free((SV *) seen);	/* Free HV */

	if (!sv) {
		TRACEME(("retrieve ERROR"));
		return &sv_undef;	/* Something went wrong, return undef */
	}

	TRACEME(("retrieve got %s(0x%lx)",
		sv_reftype(sv, FALSE), (unsigned long) sv));

	/*
	 * Build a reference to the SV returned by pretrieve even if it is
	 * already one and not a scalar, for consistency reasons.
	 *
	 * The only exception is when the sv we got is a an object, since
	 * that means it's already a reference... At store time, we already
	 * special-case this, so we must do the same now or the restored
	 * tree will be one more level deep.
	 */

	return sv_is_object(sv) ? sv : newRV_noinc(sv);
}

/*
 * pretrieve
 *
 * Retrieve data held in file and return the root object, undef on error.
 */
SV *pretrieve(f)
PerlIO *f;
{
	TRACEME(("pretrieve"));
	return do_retrieve(f);
}

/*
 * mretrieve
 *
 * Retrieve data held in scalar and return the root object, undef on error.
 */
SV *mretrieve(sv)
SV *sv;
{
	struct extendable mcommon;			/* Temporary save area for global */
	SV *rsv;							/* Retrieved SV pointer */

	TRACEME(("mretrieve"));
	StructCopy(&membuf, &mcommon, struct extendable);

	MBUF_LOAD(sv);
	rsv = do_retrieve(0);

	StructCopy(&mcommon, &membuf, struct extendable);
	return rsv;
}

/*
 * dclone
 *
 * Deep clone: returns a fresh copy of the original referenced SV tree.
 *
 * This is achieved by storing the object in memory and restoring from
 * there. Not that efficient, but it should be faster than doing it from
 * pure perl anyway.
 */
SV *dclone(sv)
SV *sv;
{
	int size;

	TRACEME(("dclone"));

	MBUF_INIT(0);
	if (!do_store(0, sv, FALSE))		/* Not in network order! */
		return &sv_undef;				/* Error during store */

	size = MBUF_SIZE();
	TRACEME(("dclone stored %d bytes", size));

	MBUF_INIT(size);
	return do_retrieve(0);
}

MODULE = Storable	PACKAGE = Storable

PROTOTYPES: ENABLE

int
pstore(f,obj)
FILE *	f
SV *	obj

int
net_pstore(f,obj)
FILE *	f
SV *	obj

SV *
mstore(obj)
SV *	obj

SV *
net_mstore(obj)
SV *	obj

SV *
pretrieve(f)
FILE *	f

SV *
mretrieve(sv)
SV *	sv

SV *
dclone(sv)
SV *	sv

