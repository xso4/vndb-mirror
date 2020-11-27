module AdvSearch.Query exposing (..)

import Json.Encode as JE
import Json.Decode as JD
import Dict
import Gen.Api as GApi

-- Generic dynamically typed representation of a query.
-- Used only as an intermediate format to help with encoding/decoding.
-- Corresponds to the compact JSON form.
type QType = V | R | C
type Op = Eq | Ne | Ge | Gt | Le | Lt
type Query
  = QAnd (List Query)
  | QOr (List Query)
  | QInt Int Op Int
  | QStr Int Op String
  | QQuery Int Op Query
  | QTuple Int Op Int Int


encodeOp : Op -> JE.Value
encodeOp o = JE.string <|
  case o of
    Eq -> "="
    Ne -> "!="
    Ge -> ">="
    Gt -> ">"
    Le -> "<="
    Lt -> "<"

encodeQuery : Query -> JE.Value
encodeQuery q =
  case q of
    QAnd l -> JE.list identity (JE.int 0 :: List.map encodeQuery l)
    QOr  l -> JE.list identity (JE.int 1 :: List.map encodeQuery l)
    QInt   s o a -> JE.list identity [JE.int s, encodeOp o, JE.int a]
    QStr   s o a -> JE.list identity [JE.int s, encodeOp o, JE.string a]
    QQuery s o a -> JE.list identity [JE.int s, encodeOp o, encodeQuery a]
    QTuple  s o a b   -> JE.list identity [JE.int s, encodeOp o, JE.int a, JE.int b]



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
    ">"  -> JD.succeed Gt
    "<=" -> JD.succeed Le
    "<"  -> JD.succeed Lt
    _    -> JD.fail "Invalid operator")

decodeQuery : JD.Decoder Query
decodeQuery = JD.index 0 JD.int |> JD.andThen (\s ->
   case s of
     0 -> JD.map QAnd decodeQList
     1 -> JD.map QOr decodeQList
     _ -> JD.oneOf
      [ JD.map2 (QInt s  ) (JD.index 1 decodeOp) (JD.index 2 JD.int)
      , JD.map2 (QStr s  ) (JD.index 1 decodeOp) (JD.index 2 JD.string)
      , JD.map2 (QQuery s) (JD.index 1 decodeOp) (JD.index 2 decodeQuery)
      , JD.map2 (\o (a,b) -> QTuple s o a b) (JD.index 1 decodeOp) <| JD.index 2 <| JD.map2 (\a b -> (a,b)) (JD.index 0 JD.int) (JD.index 1 JD.int)
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
      else if n <  1090785969 then Just <| "_" ++ encIntRaw 5 (n-17044145)
      else if n < 69810262705 then Just <| "-" ++ encIntRaw 6 (n-1090785969)
      else Nothing


encStrMap : Dict.Dict Char String
encStrMap = Dict.fromList <| List.indexedMap (\n c -> (c,"_"++Maybe.withDefault "" (encInt n))) <| String.toList " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

encStr : String -> String
encStr = String.foldl (\c s -> s ++ Maybe.withDefault (String.fromChar c) (Dict.get c encStrMap)) ""


encQuery : Query -> String
encQuery query =
  let fint n = Maybe.withDefault "" (encInt n)
      lst n l = let nl = List.map encQuery l in fint n ++ fint (List.length nl) ++ String.concat nl
      encOp o =
        case o of
          Eq -> 0
          Ne -> 1
          Ge -> 2
          Gt -> 3
          Le -> 4
          Lt -> 5
      encTypeOp o t = fint (encOp o + 8*t)
      encStrField n o v =
        let s = encStr v
            f l = fint n ++ encTypeOp o l ++ s
        in case String.length s of
                  2 -> f 2
                  3 -> f 3
                  l -> f 4 ++ "-"
  in case query of
      QAnd l -> lst 0 l
      QOr l  -> lst 1 l
      QInt n o v ->
        case encInt v of -- Integers that can't be represented in encoded form will be encoded as strings
          Just s  -> fint n ++ encTypeOp o 0 ++ s
          Nothing -> encStrField n o (String.fromInt v)
      QStr n o v -> encStrField n o v
      QQuery n o q -> fint n ++ encTypeOp o 1 ++ encQuery q
      QTuple n o a b -> fint n ++ encTypeOp o 5 ++ fint a ++ fint b


showOp : Op -> String
showOp op =
  case op of
    Eq -> "="
    Ne -> "≠"
    Le -> "≤"
    Lt -> "<"
    Ge -> "≥"
    Gt -> ">"


-- Global data that's passed around for Fields
-- (defined here because everything imports this module)
type alias Data =
  { objid        : Int -- Incremental integer for global identifiers
  , level        : Int -- Nesting level of the field being processed
  , defaultSpoil : Int
  , producers    : Dict.Dict Int GApi.ApiProducerResult
  , tags         : Dict.Dict Int GApi.ApiTagResult
  , traits       : Dict.Dict Int GApi.ApiTraitResult
  }
