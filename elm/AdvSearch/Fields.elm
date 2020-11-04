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
-- The code for nested fields is tightly coupled with the generic 'Field' abstraction below.

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
  | NType NestType Bool


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
    NField n FDel -> (dat, { model | fields = delidx n model.fields }, Cmd.none)
    NField n FMoveSub ->
      let (ndat,subm) = nestInit (if model.ntype == NAnd then NOr else NAnd) model.ftype dat
          subfields = List.drop n model.fields |> List.take 1 |> List.map (\(fid,fdd,fm) -> (fid, DD.toggle fdd False, fm))
          (ndat2,subf) = fieldCreate -1 (ndat, FMNest { subm | fields = subfields })
      in (ndat2, { model | fields = modidx n (always subf) model.fields }, Cmd.none)
    NField n m ->
      case List.head (List.drop n model.fields) of
        Nothing -> (dat, model, Cmd.none)
        Just f ->
          let (ndat, nf, nc) = fieldUpdate dat m f
          in (ndat, { model | fields = modidx n (always nf) model.fields }, Cmd.map (NField n) nc)
    NType n _ -> (dat, { model | ntype = n }, Cmd.none)


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


nestFieldView : Int -> Field -> Html FieldMsg
nestFieldView level f =
  let (fddv, fbody) = fieldView level f
  in  div [ class "advnest" ] [ fddv, fbody ]


nestView : Int -> NestModel -> (Html NestMsg, () -> List (Html NestMsg), Html NestMsg)
nestView level model =
  let
    isNest (_,(_,_,f)) =
     case f of
       FMNest _ -> True
       _ -> False
    list   = List.indexedMap (\a b -> (a,b)) model.fields
    nests  = List.filter isNest list
    plains = List.filter (not << isNest) list

    pViews = List.map (\(i,f) -> Html.map (NField i) (Tuple.first (fieldView (level+2) f))) plains
    nViews = List.map (\(i,f) -> Html.map (NField i) (nestFieldView (level+1) f)) nests

    add =
      div [ class "elm_dd_input elm_dd_noarrow" ]
      [ DD.view model.add Api.Normal (text "+") <| \() ->
        [ div [ class "advheader" ] [ h3 [] [ text "Add filter" ] ]
        , ul [] <|
          List.map (\(n,f) ->
            if f.ftype /= model.ftype || f.title == "" then text ""
            else li [] [ a [ href "#", onClickD (NAdd n)] [ text f.title ] ]
          ) <| A.toIndexedList fields
        ]
      ]

    lbl = text <| if model.ntype == NAnd then "And" else "Or"
    cont () =
      [ ul []
        [ li [] [ linkRadio (model.ntype == NAnd) (NType NAnd) [ text "And" ] ]
        , li [] [ linkRadio (model.ntype == NOr ) (NType NOr ) [ text "Or"  ] ]
        ]
      ]
    body =
      div []
        <| div [ class "advrow" ] (pViews ++ if List.isEmpty nests then [add] else [])
        :: nViews
        ++ (if List.isEmpty nests then [] else [add])
  in (lbl, cont, body)





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
  | FDel       -- intercepted in nestUpdate
  | FMoveSub   -- intercepted in nestUpdate
  | FMovePar

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
  let maps f m = (dat, (num, dd, f m), Cmd.none)              -- Simple version: update function returns a Model
      mapf fm fc (d,m,c) = (d, (num, dd, fm m), Cmd.map fc c) -- Full version: update function returns (Data, Model, Cmd)
      mapc fm fc (d,m,c) = (d, (num, DD.toggle dd False, fm m), Cmd.map fc c) -- Full version that also closes the DD (Ugly hack...)
      noop = (dat, (num, dd, model), Cmd.none)
  in case (msg_, model) of
      -- Move to parent node is tricky, needs to be intercepted at this point so that we can access the parent NestModel.
      (FSNest (NField parentNum (FSNest (NField fieldNum FMovePar))), FMNest grandModel) ->
        case List.head <| List.drop parentNum grandModel.fields of
          Just (_,_,FMNest parentModel) ->
            let fieldField = List.drop fieldNum parentModel.fields |> List.take 1
                newFields = List.map (\(fid,fdd,fm) -> (fid, DD.toggle fdd False, fm)) fieldField
                newParentModel = { parentModel | fields = delidx fieldNum parentModel.fields }
                newGrandFields =
                  (if List.isEmpty newParentModel.fields
                   then delidx parentNum grandModel.fields
                   else modidx parentNum (\(pid,pdd,_) -> (pid,pdd,FMNest newParentModel)) grandModel.fields
                  ) ++ newFields
                newGrandModel = { grandModel | fields = newGrandFields }
            in (dat, (num,dd,FMNest newGrandModel), Cmd.none)
          _ -> noop

      (FSNest (NType a b), FMNest m) -> mapc FMNest FSNest (nestUpdate dat (NType a b) m)
      (FSNest msg,     FMNest m)     -> mapf FMNest FSNest (nestUpdate dat msg m)
      (FSLang msg,     FMLang m)     -> maps FMLang     (AS.update msg m)
      (FSOLang msg,    FMOLang m)    -> maps FMOLang    (AS.update msg m)
      (FSPlatform msg, FMPlatform m) -> maps FMPlatform (AS.update msg m)
      (FSLength msg,   FMLength m)   -> maps FMLength   (AS.update msg m)
      (FToggle b, _) -> (dat, (num, DD.toggle dd b, model), Cmd.none)
      _ -> noop


fieldView : Int -> Field -> (Html FieldMsg, Html FieldMsg)
fieldView level (_, dd, model) =
  let ddv lbl cont = div [ class "elm_dd_input" ]
        [ DD.view dd Api.Normal lbl <| \() ->
            div [ class "advbut" ]
            [ if level == 0
              then b [ title "Can't delete the top-level filter" ] [ text "⊗" ]
              else a [ href "#", onClickD FDel, title "Delete this filter" ] [ text "⊗" ]
            , if level <= 1
              then b [ title "Can't move this filter to parent branch" ] [ text "↰" ]
              else a [ href "#", onClickD FMovePar, title "Move this filter to parent branch" ] [ text "↰" ]
            , a [ href "#", onClickD FMoveSub, title "Create new branch for this filter" ] [ text "↳" ]
            ] :: cont ()
        ]
      vf f (lbl,cont,body) = (ddv (Html.map f lbl) (\() -> List.map (Html.map f) (cont ())), Html.map f body)
      vs f (lbl,cont) = vf f (lbl,cont,text "")
  in case model of
      FMCustom m   -> vs FSCustom   (text "Unrecognized query", \() -> [text ""]) -- TODO: Display the Query
      FMNest m     -> vf FSNest     (nestView level m)
      FMLang  m    -> vs FSLang     (AS.langView False m)
      FMOLang m    -> vs FSOLang    (AS.langView True  m)
      FMPlatform m -> vs FSPlatform (AS.platformView m)
      FMLength m   -> vs FSLength   (AS.lengthView m)


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
