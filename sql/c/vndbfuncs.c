/* This file contains C support functions for the 'vndbid' type,
 * see sql/vndbid.sql for more information.
 */

#include "postgres.h"
#if PG_MAJORVERSION_NUM > 15
#include "varatt.h"
#endif
#include "fmgr.h"
#include "libpq/pqformat.h"
#include "utils/sortsupport.h"

PG_MODULE_MAGIC;


/* Internal representation of the vndbid is an int32,
 *    6 most significant bits are used for the type,
 *   26 least significant bits for the numeric identifier.
 *
 * Apart from the different formatting and type system considerations, these
 * identifiers are treated (compared, sorted, etc) exactly as if they were
 * regular integers.
 *
 * The order of different entry types is, uh, implementation-defined. It
 * doesn't have to make sense, it just has to have a stable order.
 */

/* List of recognized types: encoded type_id (must be stable!), string, first character, second character.
 * ASSUMPTION: 0 <= type_id <= 31, so that (vndbid-vndbid) can't overflow.
 */
#define VNDBID_TYPES\
    X( 1, "c" , 'c', 0)\
    X( 2, "d",  'd', 0)\
    X( 3, "g" , 'g', 0)\
    X( 4, "i" , 'i', 0)\
    X( 5, "p" , 'p', 0)\
    X( 6, "r" , 'r', 0)\
    X( 7, "s" , 's', 0)\
    X( 8, "v" , 'v', 0)\
    X( 9, "ch", 'c', 'h')\
    X(10, "cv", 'c', 'v')\
    X(11, "sf", 's', 'f')\
    X(12, "w",  'w', 0)\
    X(13, "u",  'u', 0)\
    X(14, "t",  't', 0)

#define VNDBID_TYPE(_x) ((_x) >> 26)
#define VNDBID_NUM(_x)  ((_x) & 0x03FFFFFF)
#define VNDBID_MAXID    ((1<<26)-1)
#define VNDBID_CREATE(_x, _y) (((_x) << 26) | (_y))


static char *vndbid_type2str(int t) {
    switch(t) {
#define X(num, str, _a, _b) case num: return str;
        VNDBID_TYPES
#undef X
    }
    return "";
}


static int vndbid_str2type(char a, char b) {
#define CHAR2(_x, _y) (((int)(_x)<<8) | (int)(_y))
    switch(CHAR2(a, b)) {
#define X(num, _a, first, second) case CHAR2(first, second): return num;
        VNDBID_TYPES
#undef X
    }
    return -1;
#undef CHAR2
}


PG_FUNCTION_INFO_V1(vndbid_in);

Datum vndbid_in(PG_FUNCTION_ARGS) {
    char *ostr = PG_GETARG_CSTRING(0);
    char *str = ostr, a = 0, b = 0;
    int type, num = 0;
    if(*str >= 'a' && *str <= 'z') a = *(str++);
    if(*str >= 'a' && *str <= 'z') b = *(str++);
    type = vndbid_str2type(a, b);

    if(type < 0 || *str == 0 || *str == '0')
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION), errmsg("invalid input syntax for type %s: \"%s\"", "vndbid", ostr)));

    /* Custom string-to-int function, we don't allow leading zeros or signs */
    while(*str >= '0' && *str <= '9' && num <= VNDBID_MAXID)
        num = num*10 + (*(str++)-'0');

    if(num > VNDBID_MAXID || *str != 0)
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION), errmsg("invalid input syntax for type %s: \"%s\"", "vndbid", ostr)));

    PG_RETURN_INT32(VNDBID_CREATE(type, num));
}


PG_FUNCTION_INFO_V1(vndbid_out);

Datum vndbid_out(PG_FUNCTION_ARGS) {
    int32 arg = PG_GETARG_INT32(0);
    PG_RETURN_CSTRING(psprintf("%s%d", vndbid_type2str(VNDBID_TYPE(arg)), (int)VNDBID_NUM(arg)));
}


PG_FUNCTION_INFO_V1(vndbid_recv);

Datum vndbid_recv(PG_FUNCTION_ARGS) {
    StringInfo buf = (StringInfo) PG_GETARG_POINTER(0);
    int32 val = pq_getmsgint(buf, sizeof(int32));
    if(!*vndbid_type2str(VNDBID_TYPE(val)))
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION), errmsg("invalid data for type vndbid")));
    PG_RETURN_INT32(val);
}


PG_FUNCTION_INFO_V1(vndbid_send);

Datum vndbid_send(PG_FUNCTION_ARGS) {
    int32 arg1 = PG_GETARG_INT32(0);
    StringInfoData buf;

    pq_begintypsend(&buf);
    pq_sendint32(&buf, arg1);
    PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}


PG_FUNCTION_INFO_V1(vndbid_cmp);
PG_FUNCTION_INFO_V1(vndbid_lt);
PG_FUNCTION_INFO_V1(vndbid_le);
PG_FUNCTION_INFO_V1(vndbid_eq);
PG_FUNCTION_INFO_V1(vndbid_ge);
PG_FUNCTION_INFO_V1(vndbid_gt);
PG_FUNCTION_INFO_V1(vndbid_ne);
Datum vndbid_cmp(PG_FUNCTION_ARGS){ PG_RETURN_INT32(PG_GETARG_INT32(0) - PG_GETARG_INT32(1)); }
Datum vndbid_lt(PG_FUNCTION_ARGS) { PG_RETURN_BOOL(PG_GETARG_INT32(0) <  PG_GETARG_INT32(1)); }
Datum vndbid_le(PG_FUNCTION_ARGS) { PG_RETURN_BOOL(PG_GETARG_INT32(0) <= PG_GETARG_INT32(1)); }
Datum vndbid_eq(PG_FUNCTION_ARGS) { PG_RETURN_BOOL(PG_GETARG_INT32(0) == PG_GETARG_INT32(1)); }
Datum vndbid_ge(PG_FUNCTION_ARGS) { PG_RETURN_BOOL(PG_GETARG_INT32(0) >= PG_GETARG_INT32(1)); }
Datum vndbid_gt(PG_FUNCTION_ARGS) { PG_RETURN_BOOL(PG_GETARG_INT32(0) >  PG_GETARG_INT32(1)); }
Datum vndbid_ne(PG_FUNCTION_ARGS) { PG_RETURN_BOOL(PG_GETARG_INT32(0) != PG_GETARG_INT32(1)); }


static int vndbid_fastcmp(Datum x, Datum y, SortSupport ssup) {
    int32 a = DatumGetInt32(x);
    int32 b = DatumGetInt32(y);
    return a-b;
}

PG_FUNCTION_INFO_V1(vndbid_sortsupport);

Datum vndbid_sortsupport(PG_FUNCTION_ARGS) {
    SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
    ssup->comparator = vndbid_fastcmp;
    PG_RETURN_VOID();
}


PG_FUNCTION_INFO_V1(vndbid_hash);

Datum vndbid_hash(PG_FUNCTION_ARGS) {
    uint32 v = PG_GETARG_INT32(0);
    /* Found in khashl.h, no clue which hash function this is, but it's short and seems to make a good attempt at mixing bits.
     * PostgresSQL's internal hash functions are not exported. */
    v += ~(v << 15);
    v ^=  (v >> 10);
    v +=  (v << 3);
    v ^=  (v >> 6);
    v += ~(v << 11);
    v ^=  (v >> 16);
    PG_RETURN_INT32(v);
}


PG_FUNCTION_INFO_V1(vndbid);

Datum vndbid(PG_FUNCTION_ARGS) {
    text *type = PG_GETARG_TEXT_PP(0);
    int32 v = PG_GETARG_INT32(1);

    int itype =
        VARSIZE(type) == VARHDRSZ + 1 ? vndbid_str2type(*((char *)VARDATA(type)), 0) :
        VARSIZE(type) == VARHDRSZ + 2 ? vndbid_str2type(*((char *)VARDATA(type)), ((char *)VARDATA(type))[1]) : -1;

    if(itype < 0 || v <= 0 || v > VNDBID_MAXID)
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION), errmsg("invalid input for type vndbid")));

    PG_RETURN_INT32(VNDBID_CREATE(itype, v));
}


PG_FUNCTION_INFO_V1(vndbid_type);

Datum vndbid_type(PG_FUNCTION_ARGS) {
    uint32 v = PG_GETARG_INT32(0);
    char *str = vndbid_type2str(VNDBID_TYPE(v));
    size_t len = strlen(str);
    text *ret = (text *) palloc(len + VARHDRSZ);
    SET_VARSIZE(ret, len + VARHDRSZ);
    memcpy(VARDATA(ret), str, len);
    PG_RETURN_TEXT_P(ret);
}


PG_FUNCTION_INFO_V1(vndbid_num);

Datum vndbid_num(PG_FUNCTION_ARGS) {
    PG_RETURN_INT32(VNDBID_NUM(PG_GETARG_INT32(0)));
}


PG_FUNCTION_INFO_V1(vndbid_max);

Datum vndbid_max(PG_FUNCTION_ARGS) {
    text *type = PG_GETARG_TEXT_PP(0);

    int itype =
        VARSIZE(type) == VARHDRSZ + 1 ? vndbid_str2type(*((char *)VARDATA(type)), 0) :
        VARSIZE(type) == VARHDRSZ + 2 ? vndbid_str2type(*((char *)VARDATA(type)), ((char *)VARDATA(type))[1]) : -1;

    if(itype < 0)
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION), errmsg("invalid input for type vndbid")));

    PG_RETURN_INT32(VNDBID_CREATE(itype, VNDBID_MAXID));
}
