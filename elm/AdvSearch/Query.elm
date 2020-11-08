module AdvSearch.Query exposing (..)

import Json.Encode as JE
import Json.Decode as JD
import Dict
import Gen.Api as GApi
import Gen.AdvSearch as GAdv

-- Generic dynamically typed representation of a query.
-- Used only as an intermediate format to help with encoding/decoding.
type Op = Eq | Ne | Ge | Le
type Query
  = QAnd (List Query)
  | QOr (List Query)
  | QInt String Op Int
  | QStr String Op String
  | QQuery String Op Query


encodeOp : Op -> JE.Value
encodeOp o = JE.string <|
  case o of
    Eq -> "="
    Ne -> "!="
    Ge -> ">="
    Le -> "<="

encodeQuery : Query -> JE.Value
encodeQuery q =
  case q of
    QAnd l -> JE.list identity (JE.string "and" :: List.map encodeQuery l)
    QOr  l -> JE.list identity (JE.string "or"  :: List.map encodeQuery l)
    QInt   s o a -> JE.list identity [JE.string s, encodeOp o, JE.int a]
    QStr   s o a -> JE.list identity [JE.string s, encodeOp o, JE.string a]
    QQuery s o a -> JE.list identity [JE.string s, encodeOp o, encodeQuery a]



-- Drops the first item in the list, decodes the rest
decodeQList : JD.Decoder (List Query)
decodeQList =
  let dec l = List.map (JD.decodeValue decodeQuery) (List.drop 1 l) -- [Result Query]
      f v r = Result.andThen (\a -> Result.map (\e -> (e::a)) v) r -- Result Query -> Result [Query] -> Result [Query]
      res l = case List.foldr f (Ok []) (dec l) of  -- Decoder [Query]
                Err e -> JD.fail (JD.errorToString e)
                Ok v  -> JD.succeed v
  in JD.list JD.value |> JD.andThen res -- [Value]

decodeOp : JD.Decoder Op
decodeOp = JD.string |> JD.andThen (\s ->
  case s of
    "="  -> JD.succeed Eq
    "!=" -> JD.succeed Ne
    ">=" -> JD.succeed Ge
    "<=" -> JD.succeed Le
    _    -> JD.fail "Invalid operator")

decodeQuery : JD.Decoder Query
decodeQuery = JD.index 0 JD.string |> JD.andThen (\s ->
   case s of
     "and" -> JD.map QAnd decodeQList
     "or"  -> JD.map QOr decodeQList
     _ -> JD.oneOf
      [ JD.map2 (QInt s  ) (JD.index 1 decodeOp) (JD.index 2 JD.int)
      , JD.map2 (QStr s  ) (JD.index 1 decodeOp) (JD.index 2 JD.string)
      , JD.map2 (QQuery s) (JD.index 1 decodeOp) (JD.index 2 decodeQuery)
      ]
   )




-- Encode a Query to the compact query format. See lib/VNWeb/AdvSearch.pm for details.

encIntAlpha : Int -> String
encIntAlpha n = String.slice n (n+1) "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-"

encIntRaw : Int -> Int -> String
encIntRaw len n = (if len > 1 then encIntRaw (len-1) (n//64) else "") ++ encIntAlpha (modBy 64 n)

encInt : Int -> Maybe String
encInt n = if n <           0 then Nothing
      else if n <          49 then Just <| encIntAlpha n
      else if n <         689 then Just <| encIntAlpha (49 + (n-49)//64) ++ encIntAlpha (modBy 64 (n-49))
      else if n <        4785 then Just <| "X" ++ encIntRaw 2 (n-689)
      else if n <      266929 then Just <| "Y" ++ encIntRaw 3 (n-4785)
      else if n <    17044145 then Just <| "Z" ++ encIntRaw 4 (n-266929)
      else if n <  1090785969 then Just <| "-" ++ encIntRaw 5 (n-17044145)
      else if n < 69810262705 then Just <| "_" ++ encIntRaw 6 (n-1090785969)
      else Nothing


encStrMap : Dict.Dict Char String
encStrMap = Dict.fromList <| List.indexedMap (\n c -> (c,"_"++Maybe.withDefault "" (encInt n))) <| String.toList " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

encStr : String -> String
encStr = String.foldl (\c s -> s ++ Maybe.withDefault (String.fromChar c) (Dict.get c encStrMap)) ""


-- XXX: Queries with unknown fields or invalid value types are silently discarded
encQuery : GAdv.QType -> Query -> String
encQuery qt query =
  let fint n = Maybe.withDefault "" (encInt n)
      lst n l =
        let nl = List.map (encQuery qt) l |> List.filter (\s -> s /= "")
        in if List.isEmpty nl then "" else fint n ++ fint (List.length nl) ++ String.concat nl
      fieldByName n = List.filter (\f -> f.qtype == qt && f.name == n) GAdv.fields |> List.head
      encOp o =
        case o of
          Eq -> 0
          Ne -> 1
          Ge -> 2
          Le -> 3
      encTypeOp o t = Maybe.withDefault "" <| encInt <| encOp o + 4*t
      encStrField o v f = let s = encStr v in fint f.num ++ encTypeOp o (String.length s + 9) ++ s
  in case query of
      QAnd l -> lst 0 l
      QOr l  -> lst 1 l
      QInt n o v -> fieldByName n |> Maybe.map (\f ->
        case encInt v of -- Integers that can't be represented in encoded form will be encoded as strings
          Just s -> fint f.num ++ encTypeOp o 0 ++ s
          Nothing -> encStrField o (String.fromInt v) f) |> Maybe.withDefault ""
      QStr n o v -> fieldByName n |> Maybe.map (encStrField o v) |> Maybe.withDefault ""
      QQuery n o q -> fieldByName n |> Maybe.andThen (\f ->
        case f.vtype of
          GAdv.QVQuery t -> Just (fint f.num ++ encTypeOp o 1 ++ encQuery t q)
          _ -> Nothing) |> Maybe.withDefault ""




-- Global data that's passed around for Fields
-- (defined here because everything imports this module)
type alias Data =
  { objid     : Int -- Incremental integer for global identifiers
  , level     : Int -- Nesting level of the field being processed
  , producers : Dict.Dict Int GApi.ApiProducerResult
  }
