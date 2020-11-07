module AdvSearch.Query exposing (..)

import Json.Encode as JE
import Json.Decode as JD
import Dict
import Gen.Api as GApi

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



-- Global data that's passed around for Fields
-- (defined here because everything imports this module)
type alias Data =
  { objid     : Int -- Incremental integer for global identifiers
  , level     : Int -- Nesting level of the field being processed
  , producers : Dict.Dict Int GApi.ApiProducerResult
  }
