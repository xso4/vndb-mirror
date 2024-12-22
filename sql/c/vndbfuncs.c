/* This file contains C support functions for the custom types defined in
 * sql/vndbid.sql, see that file for more information.
 *
 * There are support functions for three types:
 * - vndbid_*
 *   Old 32-bit vndbid, not used anymore but retained in this file in order to
 *   support importing older database dumps from backup.
 * - vndbtag_*
 *   The 16-bit vndbtag type.
 * - vndbid2_*
 *   New 64-bit vndbid that makes use of vndbtag.
 */

#include "postgres.h"
#if PG_MAJORVERSION_NUM > 15
#include "varatt.h"
#endif
#include "fmgr.h"
#include "libpq/pqformat.h"
#include "nodes/nodeFuncs.h"
#include "nodes/makefuncs.h"
#include "nodes/supportnodes.h"
#include "utils/array.h"
#include "utils/sortsupport.h"
#include "utils/lsyscache.h"

PG_MODULE_MAGIC;




/*******************************
 *          vndbid             *
 *******************************/


/* Internal representation of the old vndbid is an int32,
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




/*******************************
 *          vndbtag            *
 *******************************/


const char vndbtag_alpha[] = "\0""abcdefghijklmnopqrstuvwxyz?????";

#define VNDBTAG_1(v) (((v) >> 10) & 31)
#define VNDBTAG_2(v) (((v) >> 5) & 31)
#define VNDBTAG_3(v) ((v) & 31)

/* Advances *str to the byte after the tag. */
static int16 vndbtag_parse(char **str) {
    int16 tag = 0;
    if (**str >= 'a' && **str <= 'z') {
        tag = (**str - 'a' + 1) << 10;
        (*str)++;
        if (**str >= 'a' && **str <= 'z') {
            tag |= (**str - 'a' + 1) << 5;
            (*str)++;
            if (**str >= 'a' && **str <= 'z') {
                tag |= **str - 'a' + 1;
                (*str)++;
            }
        }
    }
    return tag;
}

/* out must have room for at least 4 bytes, string will be null-terminated. */
static char *vndbtag_fmt(int16 tag, char *out) {
    out[0] = vndbtag_alpha[VNDBTAG_1(tag)];
    out[1] = vndbtag_alpha[VNDBTAG_2(tag)];
    out[2] = vndbtag_alpha[VNDBTAG_3(tag)];
    out[3] = 0;
    return out;
}

static int vndbtag_isvalid(int16 tag) {
    return tag > 0
        && VNDBTAG_1(tag) < 27
        && VNDBTAG_2(tag) < 27
        && VNDBTAG_3(tag) < 27
        && VNDBTAG_1(tag) > 0
        && (VNDBTAG_3(tag) == 0 || VNDBTAG_2(tag) > 0);
}

PG_FUNCTION_INFO_V1(vndbtag_in);

Datum vndbtag_in(PG_FUNCTION_ARGS) {
    char *ostr = PG_GETARG_CSTRING(0);
    char *str = ostr;
    int16 tag = vndbtag_parse(&str);
    if(tag == 0 || *str)
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                 errmsg("invalid input syntax for type %s: \"%s\"",
                        "vndbtag", ostr)));
    PG_RETURN_INT16(tag);
}


PG_FUNCTION_INFO_V1(vndbtag_out);

Datum vndbtag_out(PG_FUNCTION_ARGS) {
    PG_RETURN_CSTRING(vndbtag_fmt(PG_GETARG_INT16(0), palloc(4)));
}


PG_FUNCTION_INFO_V1(vndbtag_recv);

Datum vndbtag_recv(PG_FUNCTION_ARGS) {
    StringInfo buf = (StringInfo) PG_GETARG_POINTER(0);
    int16 tag = pq_getmsgint(buf, 2);
    if (!vndbtag_isvalid(tag))
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_INVALID_BINARY_REPRESENTATION),
                 errmsg("invalid data for type vndbtag: %d", (int)tag)));
    PG_RETURN_INT16(tag);
}





/*******************************
 *          vndbid2            *
 *******************************/


#define VNDBID2_MAXNUM (((int64)1<<48)-1)
#define VNDBID2(type, num) ((((int64)type) << 48) | (num))
#define VNDBID2_TYPE(v) ((int16)((v) >> 48))
#define VNDBID2_NUM(v) ((v) & VNDBID2_MAXNUM)


PG_FUNCTION_INFO_V1(vndbid2_in);

Datum vndbid2_in(PG_FUNCTION_ARGS) {
    char *ostr = PG_GETARG_CSTRING(0);
    int32 typmod = PG_GETARG_INT32(2);
    char buf1[4], buf2[4];
    char *str = ostr;
    int64 num = 0;
    int16 tag = vndbtag_parse(&str);

    if (str == ostr || !(*str >= '1' && *str <= '9')) goto err;
    while (*str >= '0' && *str <= '9') {
        num = (10 * num) + (*str - '0');
        if (num > VNDBID2_MAXNUM) goto err;
        str++;
    }
    if (*str) goto err;
    if (typmod >= 0 && typmod != tag)
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                 errmsg("invalid tag for type vndbid, expected \"%s\" but got \"%s\"",
                        vndbtag_fmt(typmod, buf1), vndbtag_fmt(tag, buf2))));
    PG_RETURN_INT64(VNDBID2(tag, num));

err:
    ereturn(fcinfo->context, (Datum)0,
            (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
             errmsg("invalid input syntax for type %s: \"%s\"",
                    "vndbid", ostr)));
}


PG_FUNCTION_INFO_V1(vndbid2_out);

Datum vndbid2_out(PG_FUNCTION_ARGS) {
    int64 id = PG_GETARG_INT64(0);
    char buf[4];
    PG_RETURN_CSTRING(psprintf("%s"INT64_FORMAT,
                               vndbtag_fmt(VNDBID2_TYPE(id), buf),
                               VNDBID2_NUM(id)));
}


PG_FUNCTION_INFO_V1(vndbid2_typ_in);

Datum vndbid2_typ_in(PG_FUNCTION_ARGS) {
    ArrayType *arr = PG_GETARG_ARRAYTYPE_P(0);
    Datum *values;
    char *str, *ostr;
    int num, tag;

    deconstruct_array_builtin(arr, CSTRINGOID, &values, NULL, &num);
    if (num != 1)
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("invalid number of arguments for type vndbid: %d", num)));

    ostr = DatumGetCString(values[0]);
    str = ostr;
    tag = vndbtag_parse(&str);
    if (tag == 0 || *str)
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("invalid type modifier for type vndbid: \"%s\"", ostr)));
    PG_RETURN_INT32(tag);
}


PG_FUNCTION_INFO_V1(vndbid2_typ_out);

Datum vndbid2_typ_out(PG_FUNCTION_ARGS) {
    char buf[4];
    PG_RETURN_CSTRING(psprintf("(%s)", vndbtag_fmt(PG_GETARG_INT16(0), buf)));
}


PG_FUNCTION_INFO_V1(vndbid2_cast);

Datum vndbid2_cast(PG_FUNCTION_ARGS) {
    int64 id = PG_GETARG_INT64(0);
    int32 typmod = PG_GETARG_INT32(1);
    char buf1[4], buf2[4];
    if (typmod >= 0 && typmod != VNDBID2_TYPE(id))
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("invalid tag for type vndbid, expected \"%s\" but got \"%s\"",
                        vndbtag_fmt(typmod, buf1), vndbtag_fmt(VNDBID2_TYPE(id), buf2))));
    PG_RETURN_INT64(id);
}


PG_FUNCTION_INFO_V1(vndbid2_recv);

Datum vndbid2_recv(PG_FUNCTION_ARGS) {
    StringInfo buf = (StringInfo) PG_GETARG_POINTER(0);
    int64 id = pq_getmsgint64(buf);
    if (id < 0 || !vndbtag_isvalid(VNDBID2_TYPE(id)) || VNDBID2_NUM(id) == 0)
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_INVALID_BINARY_REPRESENTATION),
                 errmsg("invalid data for type vndbid: "INT64_FORMAT, id)));
    PG_RETURN_INT64(id);
}


PG_FUNCTION_INFO_V1(vndbid2);

Datum vndbid2(PG_FUNCTION_ARGS) {
    int16 tag = PG_GETARG_INT16(0);
    int64 num = PG_GETARG_INT64(1);
    if (num < 1 || num > VNDBID2_MAXNUM)
        ereturn(fcinfo->context, (Datum)0,
                (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
                 errmsg("integer out of range for vndbid: "INT64_FORMAT, num)));
    PG_RETURN_INT64(VNDBID2(tag, num));
}


PG_FUNCTION_INFO_V1(vndbid2_type);

Datum vndbid2_type(PG_FUNCTION_ARGS) {
    PG_RETURN_INT16(VNDBID2_TYPE(PG_GETARG_INT64(0)));
}


PG_FUNCTION_INFO_V1(vndbid2_istype);

Datum vndbid2_istype(PG_FUNCTION_ARGS) {
    PG_RETURN_BOOL(VNDBID2_TYPE(PG_GETARG_INT64(0)) == PG_GETARG_INT16(1));
}


/* Expand vndbid_istype() (or the ^= operator) into an indexable expression of (x >= '#1' && x <= '#max') */
static Node *vndbid2_istype_expr(Node *left, Node *right, Oid opfamily) {
    Oid idtype, ge, le;
    Expr *expr;
    int16 tag;
    List *list;

    if (!IsA(right, Const) || ((Const *)right)->constisnull) return NULL;
    if (!IsA(left, Var)) elog(ERROR, "expected left to be a var in vndbid2_istype");

    idtype = ((Var *)left)->vartype;
    ge = get_opfamily_member(opfamily, idtype, idtype, BTGreaterEqualStrategyNumber);
    le = get_opfamily_member(opfamily, idtype, idtype, BTLessEqualStrategyNumber);
    if (ge == InvalidOid || le == InvalidOid)
        elog(ERROR, "missing btree operator family for type vndbid2 (%d)", idtype);

    tag = DatumGetInt16(((Const *)right)->constvalue);

    expr = make_opclause(ge, BOOLOID, false, (Expr *)left,
            (Expr *)makeConst(idtype, -1, InvalidOid, 8, Int64GetDatum(VNDBID2(tag, 1)), false, true),
            InvalidOid, InvalidOid);
    list = list_make1(expr);

    expr = make_opclause(le, BOOLOID, false, (Expr *)left,
            (Expr *)makeConst(idtype, -1, InvalidOid, 8, Int64GetDatum(VNDBID2(tag, VNDBID2_MAXNUM)), false, true),
            InvalidOid, InvalidOid);
    list = lappend(list, expr);

    return (Node *)list;
}


PG_FUNCTION_INFO_V1(vndbid2_istype_sup);

Datum vndbid2_istype_sup(PG_FUNCTION_ARGS) {
    Node *rawreq = (Node *)PG_GETARG_POINTER(0);
    Node *ret = NULL;
    SupportRequestIndexCondition *req;

    /* Only do SupportRequestIndexCondition */
    if (!IsA(rawreq, SupportRequestIndexCondition)) PG_RETURN_POINTER(NULL);
    req = (SupportRequestIndexCondition *)rawreq;

    /* Can only index on the vndbid argument */
    if (req->indexarg != 0) PG_RETURN_POINTER(NULL);

    if (is_opclause(req->node)) {
        OpExpr *clause = (OpExpr *)req->node;
        ret = vndbid2_istype_expr(linitial(clause->args), lsecond(clause->args), req->opfamily);
    } else if (is_funcclause(req->node)) {
        FuncExpr *clause = (FuncExpr *)req->node;
        ret = vndbid2_istype_expr(linitial(clause->args), lsecond(clause->args), req->opfamily);
    }

    if (ret) req->lossy = false;
    PG_RETURN_POINTER(ret);
}


PG_FUNCTION_INFO_V1(vndbid2_num);

Datum vndbid2_num(PG_FUNCTION_ARGS) {
    PG_RETURN_INT64(VNDBID2_NUM(PG_GETARG_INT64(0)));
}


PG_FUNCTION_INFO_V1(vndbid2_max);

Datum vndbid2_max(PG_FUNCTION_ARGS) {
    PG_RETURN_INT64(VNDBID2(PG_GETARG_INT16(0), VNDBID2_MAXNUM));
}
