module AdvSearch.Fields exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Array as A
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.DropDown as DD
import Lib.Api as Api
import AdvSearch.Set as AS
import AdvSearch.Query exposing (..)


-- "Nested" fields are a container for other fields.

type NestType = NAnd | NOr

type alias NestModel =
  { ntype  : NestType
  , ftype  : FieldType
  , fields : List Field
  , add    : DD.Config NestMsg
  }


type NestMsg
  = NAddToggle Bool
  | NAdd Int
  | NField Int FieldMsg


nestInit : NestType -> FieldType -> Data -> (Data, NestModel)
nestInit n f dat = ({dat | objid = dat.objid+1 },
  { ntype  = n
  , ftype  = f
  , fields = []
  , add    = DD.init ("advsearch_field"++String.fromInt dat.objid) NAddToggle
  })


nestUpdate : Data -> NestMsg -> NestModel -> (Data, NestModel, Cmd NestMsg)
nestUpdate dat msg model =
  case msg of
    NAddToggle b -> (dat, { model | add = DD.toggle model.add b }, Cmd.none)
    NAdd n ->
      let (ndat,f) = fieldInit n dat
      in (ndat, { model | add = DD.toggle model.add False, fields = model.fields ++ [f] }, Cmd.none)
    NField n m ->
      case List.head (List.drop n model.fields) of
        Nothing -> (dat, model, Cmd.none)
        Just f ->
          let (ndat, nf, nc) = fieldUpdate dat m f
          in (ndat, { model | fields = modidx n (always nf) model.fields }, Cmd.map (NField n) nc)


nestToQuery : NestModel -> Maybe Query
nestToQuery model =
  case (model.ntype, List.filterMap fieldToQuery model.fields) of
    (_,    [] ) -> Nothing
    (_,    [x]) -> Just x
    (NAnd, xs ) -> Just (QAnd xs)
    (NOr,  xs ) -> Just (QOr xs)


nestFromQuery : NestType -> FieldType -> Data -> Query -> Maybe (Data, NestModel)
nestFromQuery ntype ftype dat q =
  let init l =
        let (ndat,m) = nestInit ntype ftype dat
            (ndat2,fl) = List.foldr (\f (d,a) -> let (nd,fm) = fieldFromQuery ftype d f in (nd,(fm::a))) (ndat,[]) l
        in Just (ndat2, { m | fields = fl })
  in case (ntype, q) of
       (NAnd, QAnd l) -> init l
       (NOr,  QOr  l) -> init l
       _ -> Nothing


-- TODO: Dropdown to display & switch between and/or
-- TODO: Buttons to move and remove fields
nestView : NestModel -> Html NestMsg
nestView model =
  let
    isNest (_,(_,_,f)) =
     case f of
       FMNest _ -> True
       _ -> False
    list   = List.indexedMap (\a b -> (a,b)) model.fields
    nests  = List.filter isNest list
    plains = List.filter (not << isNest) list
    plainsV = List.map (\(i,f) -> Html.map (NField i) (fieldView f)) plains

    add =
      div [ class "elm_dd_input elm_dd_noarrow", style "width" "13px" ]
      [ DD.view model.add Api.Normal (text "+") <| \() ->
        [ div [ class "advheader" ]
          [ h3 [] [ text "Add filter" ] ]
        , ul [] <|
          List.map (\(n,f) ->
            if f.ftype /= model.ftype || f.title == "" then text ""
            else li [] [ a [ href "#", onClickD (NAdd n)] [ text f.title ] ]
          ) <| A.toIndexedList fields
        ]
      ]

    sel = div [] [ text <| if model.ntype == NAnd then "And" else "Or" ]
  in
  div [ class "advnest" ]
  [ sel
  , div []
    <| div [ class "advrow" ] (if List.isEmpty nests then plainsV ++ [add] else plainsV)
    :: List.map (\(i,f) -> Html.map (NField i) (fieldView f)) nests
    ++ (if List.isEmpty nests then [] else [add])
  ]





-- Generic field abstraction.
-- (this is where typeclasses would have been *awesome*)
--
-- The following functions and definitions are only intended to provide field
-- listings and function dispatchers, if the implementation of anything in here
-- is longer than a single line, it should get its own definition near where
-- the rest of that field is defined.

type alias Field = (Int, DD.Config FieldMsg, FieldModel) -- The Int is the index into 'fields'

type FieldModel
  = FMCustom   Query -- A read-only placeholder for Query values that failed to parse into a Field
  | FMNest     NestModel
  | FMLang     (AS.Model String)
  | FMOLang    (AS.Model String)
  | FMPlatform (AS.Model String)
  | FMLength   (AS.Model Int)

type FieldMsg
  = FSCustom   () -- Not actually used at the moment
  | FSNest     NestMsg
  | FSLang     (AS.Msg String)
  | FSOLang    (AS.Msg String)
  | FSPlatform (AS.Msg String)
  | FSLength   (AS.Msg Int)
  | FToggle Bool

type FieldType = V

type alias FieldDesc =
  { ftype     : FieldType
  , title     : String                     -- How it's listed in the field selection menu.
  , quick     : Maybe Int                  -- Whether it should be included in the default set of fields ("quick mode") and in which order.
  , init      : Data -> (Data, FieldModel) -- How to initialize an empty field
  , fromQuery : Data -> Query -> Maybe (Data, FieldModel)  -- How to initialize the field from a query
  }


-- XXX: Should this be lazily initialized instead? May impact JS load time like this.
fields : A.Array FieldDesc
fields =
  let f ftype title quick wrap init fromq =
        { ftype     = ftype
        , title     = title
        , quick     = quick
        , init      = \d -> (Tuple.mapSecond wrap (init d))
        , fromQuery = \d q -> Maybe.map (Tuple.mapSecond wrap) (fromq d q)
        }
  in A.fromList
  -- IMPORTANT: This list is processed in reverse order when reading a Query
  -- into Fields, so "catch all" fields must be listed first. In particular,
  -- FMNest with and/or should go before everything else.

  --  T TITLE               QUICK     WRAP        INIT               FROM_QUERY
  [ f V "And"               Nothing   FMNest      (nestInit NAnd V)  (nestFromQuery NAnd V)
  , f V "Or"                Nothing   FMNest      (nestInit NOr  V)  (nestFromQuery NOr  V)

  , f V "Language"          (Just 1)  FMLang      AS.init            AS.langFromQuery
  , f V "Original language" (Just 2)  FMOLang     AS.init            AS.olangFromQuery
  , f V "Platform"          (Just 3)  FMPlatform  AS.init            AS.platformFromQuery
  , f V "Length"            (Just 4)  FMLength    AS.init            AS.lengthFromQuery
  ]


fieldUpdate : Data -> FieldMsg -> Field -> (Data, Field, Cmd FieldMsg)
fieldUpdate dat msg_ (num, dd, model) =
  let maps f m = (dat, (num, dd, (f m)), Cmd.none)              -- Simple version: update function returns a Model
      mapf fm fc (d,m,c) = (d, (num, dd, (fm m)), Cmd.map fc c) -- Full version: update function returns (Data, Model, Cmd)
  in case (msg_, model) of
      (FSNest msg,     FMNest m)     -> mapf FMNest FSNest (nestUpdate dat msg m)
      (FSLang  msg,    FMLang  m)    -> maps FMLang     (AS.update msg m)
      (FSOLang msg,    FMOLang m)    -> maps FMOLang    (AS.update msg m)
      (FSPlatform msg, FMPlatform m) -> maps FMPlatform (AS.update msg m)
      (FSLength msg,   FMLength m)   -> maps FMLength   (AS.update msg m)
      (FToggle b, _) -> (dat, (num, DD.toggle dd b, model), Cmd.none)
      _ -> (dat, (num, dd, model), Cmd.none)


fieldView : Field -> Html FieldMsg
fieldView (_, dd, model) =
  let v f (lbl,cont) = div [ class "elm_dd_input" ] [ DD.view dd Api.Normal (Html.map f lbl) <| \() -> List.map (Html.map f) (cont ()) ]
  in case model of
      FMCustom m   -> v FSCustom   (text "Unrecognized query", \() -> [text ""]) -- TODO: Display the Query
      FMNest m     -> Html.map FSNest (nestView m)
      FMLang  m    -> v FSLang     (AS.langView False m)
      FMOLang m    -> v FSOLang    (AS.langView True  m)
      FMPlatform m -> v FSPlatform (AS.platformView m)
      FMLength m   -> v FSLength   (AS.lengthView m)


fieldToQuery : Field -> Maybe Query
fieldToQuery (_, _, model) =
  case model of
    FMCustom m   -> Just m
    FMNest m     -> nestToQuery m
    FMLang  m    -> AS.toQuery (QStr "lang" ) m
    FMOLang m    -> AS.toQuery (QStr "olang") m
    FMPlatform m -> AS.toQuery (QStr "platform") m
    FMLength m   -> AS.toQuery (QInt "length") m


fieldCreate : Int -> (Data,FieldModel) -> (Data,Field)
fieldCreate fid (dat,fm) =
   ( {dat | objid = dat.objid + 1}
   , (fid, DD.init ("advsearch_field" ++ String.fromInt dat.objid) FToggle, fm)
   )


fieldInit : Int -> Data -> (Data,Field)
fieldInit n dat =
  case A.get n fields of
    Just f -> fieldCreate n (f.init dat)
    Nothing -> fieldCreate -1 (dat, FMCustom (QAnd [])) -- Shouldn't happen.


fieldFromQuery : FieldType -> Data -> Query -> (Data,Field)
fieldFromQuery ftype dat q =
  let (field, _) =
        A.foldr (\f (af,n) ->
          case (if af /= Nothing || f.ftype /= ftype then Nothing else f.fromQuery dat q) of
            Nothing -> (af,n-1)
            Just ret -> (Just (fieldCreate n ret), 0)
        ) (Nothing,A.length fields-1) fields
  in case field of
      Just ret -> ret
      Nothing -> fieldCreate -1 (dat, FMCustom q)


fieldSub : Field -> Sub FieldMsg
fieldSub (_,dd,fm) =
  case fm of
    FMNest m ->
      Sub.batch
        <| DD.sub dd
        :: Sub.map FSNest (DD.sub m.add)
        :: List.indexedMap (\i -> Sub.map (FSNest << NField i) << fieldSub) m.fields
    _ -> DD.sub dd
