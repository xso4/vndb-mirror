module AdvSearch.Fields exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Array as A
import Lib.DropDown as DD
import Lib.Api as Api
import AdvSearch.Set as AS
import AdvSearch.Query exposing (..)


-- Generic field abstraction.
-- (this is where typeclasses would have been *awesome*)
--
-- The following functions and definitions are only intended to provide field
-- listings and function dispatchers, if the implementation of anything in here
-- is longer than a single line, it should get its own definition near where
-- the rest of that field is defined.

type alias Field = (Int, DD.Config FieldMsg, FieldModel) -- The Int is the index into 'fields'

type FieldModel
  = FMCustom Query -- A read-only placeholder for Query values that failed to parse into a Field
  | FMLang     (AS.Model String)
  | FMOLang    (AS.Model String)
  | FMPlatform (AS.Model String)
  | FMLength   (AS.Model Int)

type FieldMsg
  = FSCustom   () -- Not actually used at the moment
  | FSLang     (AS.Msg String)
  | FSOLang    (AS.Msg String)
  | FSPlatform (AS.Msg String)
  | FSLength   (AS.Msg Int)
  | FToggle Bool

type FieldType = V

type alias FieldDesc =
  { ftype     : FieldType
  , title     : String                     -- How it's listed in the advanced search field selection menu (must be unique for the given ftype).
  , quick     : Maybe Int                  -- Whether it should be included in the quick search mode and in which order.
  , init      : FieldModel                 -- How to initialize an empty field
  , fromQuery : Query -> Maybe FieldModel  -- How to initialize the field from a query
  }


-- XXX: Should this be lazily initialized instead? May impact JS load time like this.
fields : A.Array FieldDesc
fields =
  let f ftype title quick wrap init fromq = { ftype = ftype, title = title, quick = quick, init = wrap init, fromQuery = Maybe.map wrap << fromq }
  in A.fromList
  --  T TITLE               QUICK     WRAP        INIT     FROM_QUERY
  [ f V "Language"          (Just 1)  FMLang      AS.init  AS.langFromQuery
  , f V "Original language" (Just 2)  FMOLang     AS.init  AS.olangFromQuery
  , f V "Platform"          (Just 3)  FMPlatform  AS.init  AS.platformFromQuery
  , f V "Length"            (Just 4)  FMLength    AS.init  AS.lengthFromQuery
  -- Custom field not included, that's only ever initialized in fqueryFromQuery
  ]


-- XXX: This needs a 'data' argument for global data such as a tag info cache
fieldUpdate : FieldMsg -> Field -> (Field, Cmd FieldMsg)
fieldUpdate msg_ (num, dd, model) =
  let map1 f m = ((num, dd, (f m)), Cmd.none)
  in case (msg_, model) of
      (FSLang  msg,    FMLang  m)    -> map1 FMLang     (AS.update msg m)
      (FSOLang msg,    FMOLang m)    -> map1 FMOLang    (AS.update msg m)
      (FSPlatform msg, FMPlatform m) -> map1 FMPlatform (AS.update msg m)
      (FSLength msg,   FMLength m)   -> map1 FMLength   (AS.update msg m)
      (FToggle b, _) -> ((num, DD.toggle dd b, model), Cmd.none)
      _ -> ((num, dd, model), Cmd.none)


fieldView : Field -> Html FieldMsg
fieldView (_, dd, model) =
  let v f (lbl,cont) = div [ class "elm_dd_input" ] [ DD.view dd Api.Normal (Html.map f lbl) <| \() -> List.map (Html.map f) (cont ()) ]
  in case model of
      FMCustom m   -> v FSCustom   (text "Unrecognized query", \() -> [text ""]) -- TODO: Display the Query
      FMLang  m    -> v FSLang     (AS.langView False m)
      FMOLang m    -> v FSOLang    (AS.langView True  m)
      FMPlatform m -> v FSPlatform (AS.platformView m)
      FMLength m   -> v FSLength   (AS.lengthView m)


fieldToQuery : Field -> Maybe Query
fieldToQuery (_, _, model) =
  case model of
    FMCustom m   -> Just m
    FMLang  m    -> AS.toQuery (QStr "lang" ) m
    FMOLang m    -> AS.toQuery (QStr "olang") m
    FMPlatform m -> AS.toQuery (QStr "platform") m
    FMLength m   -> AS.toQuery (QInt "length") m


fieldInit : Int -> Int -> Field
fieldInit n ddid =
  case A.get n fields of
    Just f -> (n, DD.init ("advsearch_field" ++ String.fromInt ddid) FToggle, f.init)
    Nothing -> (-1, DD.init "" FToggle, FMCustom (QAnd [])) -- Shouldn't happen.


fieldFromQuery : FieldType -> Int -> Query -> Maybe Field
fieldFromQuery ftype ddid q =
  Tuple.first <| A.foldl (\f a ->
    let inc = Tuple.mapSecond (\n -> n+1) a
    in if Tuple.first a /= Nothing || f.ftype /= ftype then inc
       else case f.fromQuery q of
             Nothing -> inc
             Just m -> (Just (Tuple.second a, DD.init ("advsearch_field" ++ String.fromInt ddid) FToggle, m), 0)
  ) (Nothing,0) fields




-- A Query made up of Fields. This is a higher-level and type-safe alternative
-- to Query and is what the main UI works with. An FQuery does not always
-- correspond to a Query as Fields can have empty (= nothing to filter on) or
-- invalid states. A Query does always have a corresponding FQuery - the Custom
-- field type is used as fallback in case no other Field types matches.

-- Nodes in the FQuery tree are identified by their path: a list of integers
-- that index into the list. E.g.:
--
--   FAnd              -- path = []
--   [ FField 1        -- path = [0]
--   , FOr             -- path = [1]
--     [ FField 2 ]    -- path = [1,0]
--   ]
--
-- (Alternative strategy is to throw all FQuery nodes into a Dict and have
-- FAnd/FOr refer to a list of keys instead. Not sure which strategy is more
-- convenient. Arrays may be more efficient than Lists for some operations)

type FQuery
  = FAnd (List FQuery)
  | FOr (List FQuery)
  | FField Field


fqueryToQuery : FQuery -> Maybe Query
fqueryToQuery fq =
  let lst wrap l =
        case List.filterMap fqueryToQuery l of
          []  -> Nothing
          [x] -> Just x
          xs  -> Just (wrap xs)
  in case fq of
      FAnd l -> lst QAnd l
      FOr  l -> lst QOr  l
      FField f -> fieldToQuery f


-- This algorithm is kind of slow. It walks the Query tree and tries every possible Field for each Query found.
fqueryFromQuery : FieldType -> Int -> Query -> (Int, FQuery)
fqueryFromQuery ftype ddid q =
  let lst wrap l = Tuple.mapSecond wrap <| List.foldr (\oq (did,nl) -> let (ndid, fq) = fqueryFromQuery ftype did oq in (ndid, fq::nl)) (ddid,[]) l
  in case fieldFromQuery ftype ddid q of
      Just fq -> (ddid+1, FField fq)
      Nothing ->
        case q of
          QAnd l -> lst FAnd l
          QOr  l -> lst FOr  l
          _      -> (ddid+1, FField (-1, DD.init ("advsearch_field" ++ String.fromInt ddid) FToggle, FMCustom q))


-- Update a node at the given path (unused)
--fqueryUpdate : List Int -> (FQuery -> FQuery) -> FQuery -> FQuery
--fqueryUpdate path f q =
--  case path of
--    [] -> f q
--    x::xs ->
--      case q of
--        FAnd l -> FAnd (List.indexedMap (\i e -> if i == x then fqueryUpdate xs f e else e) l)
--        FOr  l -> FOr  (List.indexedMap (\i e -> if i == x then fqueryUpdate xs f e else e) l)
--        _ -> q


-- Replace an existing node at the given path
fquerySet : List Int -> FQuery -> FQuery -> FQuery
fquerySet path new q =
  case path of
    [] -> new
    x::xs ->
      case q of
        FAnd l -> FAnd (List.indexedMap (\i e -> if i == x then fquerySet xs new e else e) l)
        FOr  l -> FOr  (List.indexedMap (\i e -> if i == x then fquerySet xs new e else e) l)
        _ -> q


-- Get the node at the given path
fqueryGet : List Int -> FQuery -> Maybe FQuery
fqueryGet path q =
  case path of
    [] -> Just q
    x::xs ->
      case q of
        FAnd l -> List.drop x l |> List.head |> Maybe.andThen (fqueryGet xs)
        FOr  l -> List.drop x l |> List.head |> Maybe.andThen (fqueryGet xs)
        _ -> Nothing


fquerySub : List Int -> (List Int -> FieldMsg -> a) -> FQuery -> Sub a
fquerySub path wrap q =
  case q of
    FAnd l -> Sub.batch <| List.indexedMap (\i -> fquerySub (i::path) wrap) l
    FOr  l -> Sub.batch <| List.indexedMap (\i -> fquerySub (i::path) wrap) l
    FField (_,dd,_) -> Sub.map (wrap (List.reverse path)) (DD.sub dd)
