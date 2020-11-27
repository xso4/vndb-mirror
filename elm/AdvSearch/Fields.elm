module AdvSearch.Fields exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Array as A
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.DropDown as DD
import Lib.Api as Api
import AdvSearch.Set as AS
import AdvSearch.Producers as AP
import AdvSearch.Tags as AG
import AdvSearch.Traits as AI
import AdvSearch.RDate as AD
import AdvSearch.Range as AR
import AdvSearch.Query exposing (..)


-- "Nested" fields are a container for other fields.
-- The code for nested fields is tightly coupled with the generic 'Field' abstraction below.

type NestType = NAnd | NOr | NRel | NRelNeg | NChar | NCharNeg

type alias NestModel =
  { ntype   : NestType
  , qtype   : QType
  , fields  : List Field
  , add     : DD.Config NestMsg
  , addtype : QType
  }


type NestMsg
  = NAddToggle Bool
  | NAdd Int
  | NAddType QType
  | NField Int FieldMsg
  | NType NestType Bool


nestInit : NestType -> QType -> List Field -> Data -> (Data, NestModel)
nestInit ntype qtype list dat =
  let
    -- Make sure that subtype nesting always has an and/or field
    addNest ndat mod =
      let (ndat2,f) = fieldCreate -1 (Tuple.mapSecond FMNest (nestInit NAnd mod.qtype mod.fields ndat))
      in  (ndat2, { mod | fields = [f] })
    ensureNest (ndat,mod) =
      case (ntype, mod.fields) of
        (NAnd, _) -> (ndat,mod)
        (NOr, _) -> (ndat,mod)
        (_, [(_,_,FMNest m)]) -> if m.ntype == NAnd || m.ntype == NOr then (ndat,mod) else addNest ndat mod
        _ -> addNest ndat mod
  in ensureNest
    ( { dat | objid = dat.objid+1 }
    , { ntype   = ntype
      , qtype   = qtype
      , fields  = list
      , add     = DD.init ("advsearch_field"++String.fromInt dat.objid) NAddToggle
      , addtype = qtype
      }
    )


nestUpdate : Data -> NestMsg -> NestModel -> (Data, NestModel, Cmd NestMsg)
nestUpdate dat msg model =
  case msg of
    NAddToggle b -> (dat, { model | add = DD.toggle model.add b, addtype = model.qtype }, Cmd.none)
    NAdd n ->
      let (ndat,f) = fieldInit n dat
          (ndat2,f2) =
            if model.qtype == model.addtype then (ndat, f) else
            let nt = case model.addtype of
                      R -> NRel
                      C -> NChar
                      _ -> NAnd
                (nd,subm) = nestInit nt model.addtype [f] ndat
            in fieldCreate -1 (nd, FMNest subm)
      in (ndat2, { model | add = DD.toggle model.add False, addtype = model.qtype, fields = model.fields ++ [f2] }, Cmd.none)
    NAddType t -> (dat, { model | addtype = t }, Cmd.none)
    NField n FDel -> (dat, { model | fields = delidx n model.fields }, Cmd.none)
    NField n FMoveSub ->
      let subfields = List.drop n model.fields |> List.take 1 |> List.map (\(fid,fdd,fm) -> (fid, DD.toggle fdd False, fm))
          (ndat,subm) = nestInit (if model.ntype == NAnd then NOr else NAnd) model.qtype subfields dat
          (ndat2,subf) = fieldCreate -1 (ndat, FMNest subm)
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
    (_,       [] ) -> Nothing
    (NRel,    [x]) -> Just (QQuery 50 Eq x)
    (NRelNeg, [x]) -> Just (QQuery 50 Ne x)
    (NChar,   [x]) -> Just (QQuery 51 Eq x)
    (NCharNeg,[x]) -> Just (QQuery 51 Ne x)
    (_,       [x]) -> Just x
    (NAnd,    xs ) -> Just (QAnd xs)
    (NOr,     xs ) -> Just (QOr xs)
    _              -> Nothing


nestFromQuery : NestType -> QType -> Data -> Query -> Maybe (Data, NestModel)
nestFromQuery ntype qtype dat q =
  let init nt qt l =
        let (ndat,fl) = List.foldr (\f (d,a) -> let (nd,fm) = fieldFromQuery qt d f in (nd,(fm::a))) (dat,[]) l
        in nestInit nt qt fl ndat

      initSub op nt ntNeg qt val =
        case op of
          Eq -> Just (init nt    qt [val])
          Ne -> Just (init ntNeg qt [val])
          _ -> Nothing
  in case (qtype, ntype, q) of
       (V, NRel,  QQuery 50 op r) -> initSub op NRel  NRelNeg  R r
       (V, NChar, QQuery 51 op r) -> initSub op NChar NCharNeg C r
       (_, NAnd, QAnd l) -> Just (init NAnd qtype l)
       (_, NOr,  QOr  l) -> Just (init NOr  qtype l)
       _ -> Nothing


nestFieldView : Data -> Field -> Html FieldMsg
nestFieldView dat f =
  let (fddv, fbody) = fieldView dat f
      showDd = case f of
                (_,_,FMNest m) -> (m.ntype /= NAnd && m.ntype /= NOr) || List.length m.fields > 1
                _ -> False
  in if showDd then div [ class "advnest" ] [ fddv, fbody ] else fbody


nestView : Data -> NestModel -> (Html NestMsg, () -> List (Html NestMsg), Html NestMsg)
nestView dat model =
  let
    isNest (_,(_,_,f)) =
     case f of
       FMNest _ -> True
       _ -> False
    list   = List.indexedMap (\a b -> (a,b)) model.fields
    nests  = List.filter isNest list
    plains = List.filter (not << isNest) list
    subtype = model.ntype /= NAnd && model.ntype /= NOr

    pViews = List.map (\(i,f) -> Html.map (NField i) (Tuple.first (fieldView { dat | level = if subtype then 0 else dat.level+1 } f))) plains
    nViews = List.map (\(i,f) -> Html.map (NField i) (nestFieldView { dat | level = if subtype then 0 else dat.level+1 } f)) nests

    add =
      if model.ntype /= NAnd && model.ntype /= NOr then text "" else
      div [ class "elm_dd_input elm_dd_noarrow" ]
      [ DD.view model.add Api.Normal (text "+") <| \() ->
        [ div [ class "advheader", style "width" "200px" ]
          [ h3 [] [ text "Add filter" ]
          , div [ class "opts" ] <|
            let opts = case model.qtype of
                        V -> [ V, R, C ]
                        C -> []
                        R -> []
                f t = case t of
                       V -> "VN"
                       R -> "Release"
                       C -> "Character"
            in List.map (\t -> if t == model.addtype then b [] [ text (f t) ] else a [ href "#", onClickD (NAddType t) ] [ text (f t) ]) opts
          ]
        , ul [] <|
          List.map (\(n,f) ->
            if f.qtype /= model.addtype || f.title == "" then text ""
            else li [] [ a [ href "#", onClickD (NAdd n)] [ text f.title ] ]
          ) <| A.toIndexedList fields
        ]
      ]

    lbl = text <|
      case model.ntype of
        NAnd    -> "And"
        NOr     -> "Or"
        NRel    -> "Rel"
        NRelNeg -> "¬Rel"
        NChar   -> "Char"
        NCharNeg-> "¬Char"

    cont () =
      [ ul [] <|
        if model.ntype == NAnd || model.ntype == NOr
        then [ li [] [ linkRadio (model.ntype == NAnd) (NType NAnd) [ text "And: All filters must match" ] ]
             , li [] [ linkRadio (model.ntype == NOr ) (NType NOr ) [ text "Or: At least one filter must match"  ] ]
             ]
        else if model.ntype == NRel || model.ntype == NRelNeg
        then [ li [] [ linkRadio (model.ntype == NRel)    (NType NRel)    [ text "Has a release that matches these filters" ] ]
             , li [] [ linkRadio (model.ntype == NRelNeg) (NType NRelNeg) [ text "Does not have a release that matches these filters" ] ]
             ]
        else [ li [] [ linkRadio (model.ntype == NChar)    (NType NChar)    [ text "Has a character that matches these filters" ] ]
             , li [] [ linkRadio (model.ntype == NCharNeg) (NType NCharNeg) [ text "Does not have a character that matches these filters" ] ]
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
  | FMRole     (AS.Model String)
  | FMBlood    (AS.Model String)
  | FMSexChar  (AS.Model String)
  | FMSexSpoil (AS.Model String)
  | FMHeight   (AR.Model Int)
  | FMWeight   (AR.Model Int)
  | FMBust     (AR.Model Int)
  | FMWaist    (AR.Model Int)
  | FMHips     (AR.Model Int)
  | FMCup      (AR.Model String)
  | FMAge      (AR.Model Int)
  | FMPopularity (AR.Model Int)
  | FMRating     (AR.Model Int)
  | FMVotecount  (AR.Model Int)
  | FMDeveloper AP.Model
  | FMRDate    AD.Model
  | FMTag      AG.Model
  | FMTrait    AI.Model

type FieldMsg
  = FSCustom   () -- Not actually used at the moment
  | FSNest     NestMsg
  | FSLang     (AS.Msg String)
  | FSOLang    (AS.Msg String)
  | FSPlatform (AS.Msg String)
  | FSLength   (AS.Msg Int)
  | FSRole     (AS.Msg String)
  | FSBlood    (AS.Msg String)
  | FSSexChar  (AS.Msg String)
  | FSSexSpoil (AS.Msg String)
  | FSHeight   AR.Msg
  | FSWeight   AR.Msg
  | FSBust     AR.Msg
  | FSWaist    AR.Msg
  | FSHips     AR.Msg
  | FSCup      AR.Msg
  | FSAge      AR.Msg
  | FSPopularity AR.Msg
  | FSRating     AR.Msg
  | FSVotecount  AR.Msg
  | FSDeveloper AP.Msg
  | FSRDate    AD.Msg
  | FSTag      AG.Msg
  | FSTrait    AI.Msg
  | FToggle Bool
  | FDel       -- intercepted in nestUpdate
  | FMoveSub   -- intercepted in nestUpdate
  | FMovePar

type alias FieldDesc =
  { qtype     : QType
  , title     : String                     -- How it's listed in the field selection menu.
  , quick     : Maybe Int                  -- Whether it should be included in the default set of fields ("quick mode") and in which order.
  , init      : Data -> (Data, FieldModel) -- How to initialize an empty field
  , fromQuery : Data -> Query -> Maybe (Data, FieldModel)  -- How to initialize the field from a query
  }


-- XXX: Should this be lazily initialized instead? May impact JS load time like this.
fields : A.Array FieldDesc
fields =
  let f qtype title quick wrap init fromq =
        { qtype     = qtype
        , title     = title
        , quick     = quick
        , init      = \d -> (Tuple.mapSecond wrap (init d))
        , fromQuery = \d q -> Maybe.map (Tuple.mapSecond wrap) (fromq d q)
        }
  in A.fromList
  -- IMPORTANT: This list is processed in reverse order when reading a Query
  -- into Fields, so "catch all" fields must be listed first. In particular,
  -- FMNest with and/or should go before everything else.

  --  T TITLE               QUICK     WRAP        INIT                  FROM_QUERY
  [ f V ""                  Nothing   FMNest      (nestInit NAnd V [])  (nestFromQuery NAnd V)
  , f V ""                  Nothing   FMNest      (nestInit NOr  V [])  (nestFromQuery NOr  V)
  , f R ""                  Nothing   FMNest      (nestInit NAnd R [])  (nestFromQuery NAnd R)
  , f R ""                  Nothing   FMNest      (nestInit NOr  R [])  (nestFromQuery NOr  R)
  , f C ""                  Nothing   FMNest      (nestInit NAnd C [])  (nestFromQuery NAnd C)
  , f C ""                  Nothing   FMNest      (nestInit NOr  C [])  (nestFromQuery NOr  C)

  , f V "Language"          (Just 1)  FMLang      AS.init               AS.langFromQuery
  , f V "Original language" (Just 2)  FMOLang     AS.init               AS.olangFromQuery
  , f V "Platform"          (Just 3)  FMPlatform  AS.init               AS.platformFromQuery
  , f V "Tags"              (Just 4)  FMTag       AG.init               (AG.fromQuery -1)
  , f V ""                  Nothing   FMTag       AG.init               (AG.fromQuery 0)
  , f V ""                  Nothing   FMTag       AG.init               (AG.fromQuery 1)
  , f V ""                  Nothing   FMTag       AG.init               (AG.fromQuery 2)
  , f V "Length"            Nothing   FMLength    AS.init               AS.lengthFromQuery
  , f V "Developer"         Nothing   FMDeveloper AP.init               AP.devFromQuery
  , f V "Release date"      Nothing   FMRDate     AD.init               AD.fromQuery
  , f V "Popularity"        Nothing   FMPopularity AR.popularityInit    AR.popularityFromQuery
  , f V "Rating"            Nothing   FMRating    AR.ratingInit         AR.ratingFromQuery
  , f V "Number of votes"   Nothing   FMVotecount AR.votecountInit      AR.votecountFromQuery
  , f V ""                  Nothing   FMNest      (nestInit NRel  R []) (nestFromQuery NRel  V)
  , f V ""                  Nothing   FMNest      (nestInit NChar C []) (nestFromQuery NChar V)

  , f R "Language"          (Just 1)  FMLang      AS.init               AS.langFromQuery
  , f R "Platform"          (Just 2)  FMPlatform  AS.init               AS.platformFromQuery
  , f R "Developer"         Nothing   FMDeveloper AP.init               AP.devFromQuery
  , f R "Release date"      Nothing   FMRDate     AD.init               AD.fromQuery

  , f C "Role"              (Just 1)  FMRole      AS.init               AS.roleFromQuery
  , f C "Age"               Nothing   FMAge       AR.ageInit            AR.ageFromQuery
  , f C "Sex"               (Just 2)  FMSexChar   AS.init               (AS.sexFromQuery AS.SexChar)
  , f C "Sex (spoiler)"     Nothing   FMSexSpoil  AS.init               (AS.sexFromQuery AS.SexSpoil)
  , f C "Traits"            (Just 3)  FMTrait     AI.init               (AI.fromQuery -1)
  , f C ""                  Nothing   FMTrait     AI.init               (AI.fromQuery 0)
  , f C ""                  Nothing   FMTrait     AI.init               (AI.fromQuery 1)
  , f C ""                  Nothing   FMTrait     AI.init               (AI.fromQuery 2)
  , f C "Blood type"        Nothing   FMBlood     AS.init               AS.bloodFromQuery
  , f C "Height"            Nothing   FMHeight    AR.heightInit         AR.heightFromQuery
  , f C "Weight"            Nothing   FMWeight    AR.weightInit         AR.weightFromQuery
  , f C "Bust"              Nothing   FMBust      AR.bustInit           AR.bustFromQuery
  , f C "Waist"             Nothing   FMWaist     AR.waistInit          AR.waistFromQuery
  , f C "Hips"              Nothing   FMHips      AR.hipsInit           AR.hipsFromQuery
  , f C "Cup size"          Nothing   FMCup       AR.cupInit            AR.cupFromQuery
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
      (FSRole msg,     FMRole m)     -> maps FMRole     (AS.update msg m)
      (FSBlood msg,    FMBlood m)    -> maps FMBlood    (AS.update msg m)
      (FSSexChar msg,  FMSexChar m)  -> maps FMSexChar  (AS.update msg m)
      (FSSexSpoil msg, FMSexSpoil m) -> maps FMSexSpoil (AS.update msg m)
      (FSHeight msg,   FMHeight m)   -> maps FMHeight   (AR.update msg m)
      (FSWeight msg,   FMWeight m)   -> maps FMWeight   (AR.update msg m)
      (FSBust msg,     FMBust m)     -> maps FMBust     (AR.update msg m)
      (FSWaist msg,    FMWaist m)    -> maps FMWaist    (AR.update msg m)
      (FSHips msg,     FMHips m)     -> maps FMHips     (AR.update msg m)
      (FSCup msg,      FMCup m)      -> maps FMCup      (AR.update msg m)
      (FSAge msg,      FMAge m)      -> maps FMAge      (AR.update msg m)
      (FSPopularity msg,FMPopularity m)->maps FMPopularity (AR.update msg m)
      (FSRating msg,   FMRating m)   -> maps FMRating    (AR.update msg m)
      (FSVotecount msg,FMVotecount m)-> maps FMVotecount (AR.update msg m)
      (FSDeveloper msg,FMDeveloper m)-> mapf FMDeveloper FSDeveloper (AP.update dat msg m)
      (FSRDate msg,    FMRDate m)    -> maps FMRDate    (AD.update msg m)
      (FSTag msg,      FMTag m)      -> mapf FMTag FSTag     (AG.update dat msg m)
      (FSTrait msg,    FMTrait m)    -> mapf FMTrait FSTrait (AI.update dat msg m)
      (FToggle b, _) -> (dat, (num, DD.toggle dd b, model), Cmd.none)
      _ -> noop


fieldView : Data -> Field -> (Html FieldMsg, Html FieldMsg)
fieldView dat (_, dd, model) =
  let ddv lbl cont = div [ class "elm_dd_input" ]
        [ DD.view dd Api.Normal lbl <| \() ->
            div [ class "advbut" ]
            [ if dat.level == 0
              then b [ title "Can't delete the top-level filter" ] [ text "⊗" ]
              else a [ href "#", onClickD FDel, title "Delete this filter" ] [ text "⊗" ]
            , if dat.level <= 1
              then b [ title "Can't move this filter to parent branch" ] [ text "↰" ]
              else a [ href "#", onClickD FMovePar, title "Move this filter to parent branch" ] [ text "↰" ]
            , if dat.level == 0
              then b [ title "Can't move this filter into a subbranch" ] [ text "↳" ]
              else a [ href "#", onClickD FMoveSub, title "Create new branch for this filter" ] [ text "↳" ]
            ] :: cont ()
        ]
      vf f (lbl,cont,body) = (ddv (Html.map f lbl) (\() -> List.map (Html.map f) (cont ())), Html.map f body)
      vs f (lbl,cont) = vf f (lbl,cont,text "")
  in case model of
      FMCustom m   -> vs FSCustom   (text "Unrecognized query", \() -> [text ""]) -- TODO: Display the Query
      FMNest m     -> vf FSNest     (nestView dat m)
      FMLang  m    -> vs FSLang     (AS.langView False m)
      FMOLang m    -> vs FSOLang    (AS.langView True  m)
      FMPlatform m -> vs FSPlatform (AS.platformView m)
      FMLength m   -> vs FSLength   (AS.lengthView m)
      FMRole m     -> vs FSRole     (AS.roleView m)
      FMBlood m    -> vs FSBlood    (AS.bloodView m)
      FMSexChar m  -> vs FSSexChar  (AS.sexView AS.SexChar m)
      FMSexSpoil m -> vs FSSexSpoil (AS.sexView AS.SexSpoil m)
      FMHeight m   -> vs FSHeight   (AR.heightView m)
      FMWeight m   -> vs FSWeight   (AR.weightView m)
      FMBust m     -> vs FSBust     (AR.bustView m)
      FMWaist m    -> vs FSWaist    (AR.waistView m)
      FMHips m     -> vs FSHips     (AR.hipsView m)
      FMCup m      -> vs FSCup      (AR.cupView m)
      FMAge m      -> vs FSAge      (AR.ageView m)
      FMPopularity m->vs FSPopularity(AR.popularityView m)
      FMRating m   -> vs FSRating   (AR.ratingView m)
      FMVotecount m-> vs FSVotecount(AR.votecountView m)
      FMDeveloper m-> vs FSDeveloper(AP.devView dat m)
      FMRDate m    -> vs FSRDate    (AD.view m)
      FMTag m      -> vs FSTag      (AG.view dat m)
      FMTrait m    -> vs FSTrait    (AI.view dat m)


fieldToQuery : Field -> Maybe Query
fieldToQuery (_, _, model) =
  case model of
    FMCustom m   -> Just m
    FMNest m     -> nestToQuery m
    FMLang  m    -> AS.toQuery (QStr 2) m
    FMOLang m    -> AS.toQuery (QStr 3) m
    FMPlatform m -> AS.toQuery (QStr 4) m
    FMLength m   -> AS.toQuery (QInt 5) m
    FMRole m     -> AS.toQuery (QStr 2) m
    FMBlood m    -> AS.toQuery (QStr 3) m
    FMSexChar m  -> AS.toQuery (QStr 4) m
    FMSexSpoil m -> AS.toQuery (QStr 5) m
    FMHeight m   -> AR.toQuery (QInt 6) m
    FMWeight m   -> AR.toQuery (QInt 7) m
    FMBust m     -> AR.toQuery (QInt 8) m
    FMWaist m    -> AR.toQuery (QInt 9) m
    FMHips m     -> AR.toQuery (QInt 10) m
    FMCup m      -> AR.toQuery (QStr 11) m
    FMAge m      -> AR.toQuery (QInt 12) m
    FMPopularity m->AR.toQuery (QInt 9) m
    FMRating m   -> AR.toQuery (QInt 10) m
    FMVotecount m-> AR.toQuery (QInt 11) m
    FMDeveloper m-> AP.toQuery (QInt 6) m
    FMRDate m    -> AD.toQuery m
    FMTag m      -> AG.toQuery m
    FMTrait m    -> AI.toQuery m


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


fieldFromQuery : QType -> Data -> Query -> (Data,Field)
fieldFromQuery qtype dat q =
  let (field, _) =
        A.foldr (\f (af,n) ->
          case (if af /= Nothing || f.qtype /= qtype then Nothing else f.fromQuery dat q) of
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
