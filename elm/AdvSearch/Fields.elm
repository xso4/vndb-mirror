module AdvSearch.Fields exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Array
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.DropDown as DD
import Lib.Api as Api
import Lib.Autocomplete as A
import AdvSearch.Set as AS
import AdvSearch.Producers as AP
import AdvSearch.Tags as AG
import AdvSearch.Traits as AI
import AdvSearch.RDate as AD
import AdvSearch.Range as AR
import AdvSearch.Resolution as AE
import AdvSearch.Lib exposing (..)


-- "Nested" fields are a container for other fields.
-- The code for nested fields is tightly coupled with the generic 'Field' abstraction below.

type alias NestModel =
  { ptype   : QType -- type of the parent field
  , qtype   : QType -- type of the child fields
  , fields  : List Field
  , and     : Bool
  , andDd   : DD.Config FieldMsg
  , addDd   : DD.Config FieldMsg
  , addtype : QType
  , neg     : Bool -- only if ptype /= qtype
  }


type NestMsg
  = NAndToggle Bool
  | NAnd Bool Bool
  | NAddToggle Bool
  | NAdd Int
  | NAddType QType
  | NField Int FieldMsg
  | NNeg Bool Bool


nestInit : Bool -> QType -> QType -> List Field -> Data -> (Data, NestModel)
nestInit and ptype qtype list dat =
  ( { dat | objid = dat.objid+2 }
  , { ptype   = ptype
    , qtype   = qtype
    , fields  = list
    , and     = and
    , andDd   = DD.init ("advsearch_field"++String.fromInt (dat.objid+0)) (FSNest << NAndToggle)
    , addDd   = DD.init ("advsearch_field"++String.fromInt (dat.objid+1)) (FSNest << NAddToggle)
    , addtype = qtype
    , neg     = False
    }
  )


nestUpdate : Data -> NestMsg -> NestModel -> (Data, NestModel, Cmd NestMsg)
nestUpdate dat msg model =
  case msg of
    NAndToggle b -> (dat, { model | andDd = DD.toggle model.andDd b, addtype = model.qtype }, Cmd.none)
    NAnd b _ -> (dat, { model | and = b, andDd = DD.toggle model.andDd False }, Cmd.none)
    NAddToggle b -> (dat, { model | addDd = DD.toggle model.addDd b }, Cmd.none)
    NAdd n ->
      let (ndat,f) = fieldInit n dat
          (ndat2,f2) =
            if model.qtype == model.addtype then (ndat, f) else
            let (nd,subm) = nestInit True model.qtype model.addtype [f] ndat
            in fieldCreate -1 (nd, FMNest subm)
      in (ndat2, { model | addDd = DD.toggle model.addDd False, addtype = model.qtype, fields = model.fields ++ [f2] }, Cmd.none)
    NAddType t -> (dat, { model | addtype = t }, Cmd.none)
    NField n FDel -> (dat, { model | fields = delidx n model.fields }, Cmd.none)
    NField n FMoveSub ->
      let subfields = List.drop n model.fields |> List.take 1 |> List.map (\(fid,fdd,fm) -> (fid, DD.toggle fdd False, fm))
          (ndat,subm) = nestInit (not model.and) model.qtype model.qtype subfields dat
          (ndat2,subf) = fieldCreate -1 (ndat, FMNest subm)
      in (ndat2, { model | fields = modidx n (always subf) model.fields }, Cmd.none)
    NField n m ->
      case List.head (List.drop n model.fields) of
        Nothing -> (dat, model, Cmd.none)
        Just f ->
          let (ndat, nf, nc) = fieldUpdate dat m f
          in (ndat, { model | fields = modidx n (always nf) model.fields }, Cmd.map (NField n) nc)
    NNeg b _ -> (dat, { model | neg = b }, Cmd.none)


nestToQuery : NestModel -> Maybe Query
nestToQuery model =
  let op  = if model.neg then Ne   else Eq
      com = if model.and then QAnd else QOr
      wrap f =
        case List.filterMap fieldToQuery model.fields of
          []  -> Nothing
          [x] -> Just (f x)
          xs  -> Just (f (com xs))
  in case (model.ptype, model.qtype) of
      (V,  R) -> wrap (QQuery 50 op)
      (V,  C) -> wrap (QQuery 51 op)
      _       -> wrap identity


nestFromQuery : QType -> QType -> Data -> Query -> Maybe (Data, NestModel)
nestFromQuery ptype qtype dat q =
  let init and neg l =
        let (ndat,fl) = List.foldr (\f (d,a) -> let (nd,fm) = fieldFromQuery qtype d f in (nd,(fm::a))) (dat,[]) l
            (ndat2,m) = nestInit and ptype qtype fl ndat
        in (ndat2, { m | neg = neg })

      initSub op val =
        case (op, val) of
          (Eq, QAnd l) -> Just (init True  False l)
          (Ne, QAnd l) -> Just (init True  True  l)
          (Eq, QOr  l) -> Just (init False False l)
          (Ne, QOr  l) -> Just (init False True  l)
          (Eq,      x) -> Just (init True  False [x])
          (Ne,      x) -> Just (init True  True  [x])
          _ -> Nothing
  in case (ptype, qtype, q) of
       (V, R, QQuery 50 op r) -> initSub op r
       (V, C, QQuery 51 op r) -> initSub op r
       (_, _, QAnd l) -> if ptype == qtype then Just (init True  False l) else Nothing
       (_, _, QOr  l) -> if ptype == qtype then Just (init False False l) else Nothing
       _ -> Nothing


nestView : Data -> DD.Config FieldMsg -> NestModel -> Html FieldMsg
nestView dat dd model =
  let
    isNest (_,_,f) =
     case f of
       FMNest _ -> True
       _ -> False
    hasNest = List.any isNest model.fields
    filters = List.indexedMap (\i f ->
        Html.map (FSNest << NField i) <| fieldView { dat | level = if model.ptype /= model.qtype then 1 else dat.level+1 } f
      ) model.fields

    add =
      div [ class "elm_dd_input elm_dd_noarrow short" ]
      [ DD.view model.addDd Api.Normal (text "+") <| \() ->
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
            in List.map (\t -> if t == model.addtype then b [] [ text (f t) ] else a [ href "#", onClickD (FSNest <| NAddType t) ] [ text (f t) ]) opts
          ]
        , ul [] <|
          List.map (\(n,f) ->
            if f.qtype /= model.addtype || f.title == "" then text ""
            else li [] [ a [ href "#", onClickD (FSNest <| NAdd n)] [ text f.title ] ]
          ) <| Array.toIndexedList fields
        ]
      ]

    andcont () = [ ul []
      [ li [] [ linkRadio (    model.and) (FSNest << NAnd True ) [ text "And: All filters must match" ] ]
      , li [] [ linkRadio (not model.and) (FSNest << NAnd False) [ text "Or: At least one filter must match"  ] ]
      ] ]

    andlbl = text <| if model.and then "And" else "Or"

    and = div [ class "elm_dd_input short" ] [ DD.view model.andDd Api.Normal andlbl andcont ]

    negcont () =
      let (a,b) =
            case model.qtype of
              C -> ("Has a character that matches these filters", "Does not have a character that matches these filters")
              R -> ("Has a release that matches these filters", "Does not have a release that matches these filters")
              _ -> ("","")
      in [ ul []
        [ li [] [ linkRadio (not model.neg) (FSNest << NNeg False) [ text a ] ]
        , li [] [ linkRadio (    model.neg) (FSNest << NNeg True ) [ text b ] ]
        ] ]

    neglbl = text <| (if model.neg then "¬" else "") ++ if model.qtype == C then "Char" else "Rel"

    ourdd =
      if model.qtype == model.ptype
      then fieldViewDd dat dd andlbl andcont
      else fieldViewDd dat dd neglbl negcont

    initialdd = if model.ptype == model.qtype || List.length model.fields == 1 then [ ourdd, add ] else [ ourdd, and, add ]

  in
    if hasNest
    then table [ class "advnest" ] <| List.indexedMap (\i f -> tr []
          [ td [] <| if i == 0 then initialdd else [ b [ class "grayedout" ] [ andlbl ] ]
          , td [] [ f ]
          ]) filters
    else div [ class "advrow" ] (initialdd ++ [b [ class "grayedout" ] [ text " → " ]] ++ filters)





-- Generic field abstraction.
-- (this is where typeclasses would have been *awesome*)
--
-- The following functions and definitions are only intended to provide field
-- listings and function dispatchers, if the implementation of anything in here
-- is longer than a single line, it should get its own definition near where
-- the rest of that field is defined.

type alias Field = (Int, DD.Config FieldMsg, FieldModel) -- The Int is the index into 'fields'

type FieldModel
  = FMCustom     Query -- A read-only placeholder for Query values that failed to parse into a Field
  | FMNest       NestModel
  | FMLang       (AS.Model String)
  | FMOLang      (AS.Model String)
  | FMPlatform   (AS.Model String)
  | FMLength     (AS.Model Int)
  | FMRole       (AS.Model String)
  | FMBlood      (AS.Model String)
  | FMSexChar    (AS.Model String)
  | FMSexSpoil   (AS.Model String)
  | FMHeight     (AR.Model Int)
  | FMWeight     (AR.Model Int)
  | FMBust       (AR.Model Int)
  | FMWaist      (AR.Model Int)
  | FMHips       (AR.Model Int)
  | FMCup        (AR.Model String)
  | FMAge        (AR.Model Int)
  | FMPopularity (AR.Model Int)
  | FMRating     (AR.Model Int)
  | FMVotecount  (AR.Model Int)
  | FMDeveloper  AP.Model
  | FMRDate      AD.Model
  | FMResolution AE.Model
  | FMTag        AG.Model
  | FMTrait      AI.Model

type FieldMsg
  = FSCustom     () -- Not actually used at the moment
  | FSNest       NestMsg
  | FSLang       (AS.Msg String)
  | FSOLang      (AS.Msg String)
  | FSPlatform   (AS.Msg String)
  | FSLength     (AS.Msg Int)
  | FSRole       (AS.Msg String)
  | FSBlood      (AS.Msg String)
  | FSSexChar    (AS.Msg String)
  | FSSexSpoil   (AS.Msg String)
  | FSHeight     AR.Msg
  | FSWeight     AR.Msg
  | FSBust       AR.Msg
  | FSWaist      AR.Msg
  | FSHips       AR.Msg
  | FSCup        AR.Msg
  | FSAge        AR.Msg
  | FSPopularity AR.Msg
  | FSRating     AR.Msg
  | FSVotecount  AR.Msg
  | FSDeveloper  AP.Msg
  | FSRDate      AD.Msg
  | FSResolution AE.Msg
  | FSTag        AG.Msg
  | FSTrait      AI.Msg
  | FToggle Bool
  | FDel       -- intercepted in nestUpdate
  | FMoveSub   -- intercepted in nestUpdate
  | FMovePar

type alias FieldDesc =
  { qtype     : QType
  , title     : String                     -- How it's listed in the field selection menu.
  , quick     : Int                        -- Whether it should be included in the default set of fields (>0) ("quick mode") and in which order.
  , init      : Data -> (Data, FieldModel) -- How to initialize an empty field
  , fromQuery : Data -> Query -> Maybe (Data, FieldModel)  -- How to initialize the field from a query
  }


-- XXX: Should this be lazily initialized instead? May impact JS load time like this.
fields : Array.Array FieldDesc
fields =
  let f qtype title quick wrap init fromq =
        { qtype     = qtype
        , title     = title
        , quick     = quick
        , init      = \d -> (Tuple.mapSecond wrap (init d))
        , fromQuery = \d q -> Maybe.map (Tuple.mapSecond wrap) (fromq d q)
        }
  in Array.fromList
  -- IMPORTANT: This list is processed in reverse order when reading a Query
  -- into Fields, so "catch all" fields must be listed first. In particular,
  -- FMNest with qtype == ptype go before everything else.

  --  T TITLE            QUICK  WRAP          INIT                    FROM_QUERY
  [ f V ""                   0  FMNest        (nestInit True V V [])  (nestFromQuery V V) -- and/or's
  , f R ""                   0  FMNest        (nestInit True V R [])  (nestFromQuery R R)
  , f C ""                   0  FMNest        (nestInit True C C [])  (nestFromQuery C C)

  , f V "Language"           1  FMLang        AS.init                 AS.langFromQuery
  , f V "Original language"  2  FMOLang       AS.init                 AS.olangFromQuery
  , f V "Platform"           3  FMPlatform    AS.init                 AS.platformFromQuery
  , f V "Tags"               4  FMTag         AG.init                 (AG.fromQuery -1)
  , f V ""                   0  FMTag         AG.init                 (AG.fromQuery 0)
  , f V ""                   0  FMTag         AG.init                 (AG.fromQuery 1)
  , f V ""                   0  FMTag         AG.init                 (AG.fromQuery 2)
  , f V "Length"             0  FMLength      AS.init                 AS.lengthFromQuery
  , f V "Developer"          0  FMDeveloper   AP.init                 AP.devFromQuery
  , f V "Release date"       0  FMRDate       AD.init                 AD.fromQuery
  , f V "Popularity"         0  FMPopularity  AR.popularityInit       AR.popularityFromQuery
  , f V "Rating"             0  FMRating      AR.ratingInit           AR.ratingFromQuery
  , f V "Number of votes"    0  FMVotecount   AR.votecountInit        AR.votecountFromQuery
  , f V ""                   0  FMNest        (nestInit True V R [])  (nestFromQuery V R) -- release subtype
  , f V ""                   0  FMNest        (nestInit True V C [])  (nestFromQuery V C) -- character subtype

  , f R "Language"           1  FMLang        AS.init                 AS.langFromQuery
  , f R "Platform"           2  FMPlatform    AS.init                 AS.platformFromQuery
  , f R "Developer"          0  FMDeveloper   AP.init                 AP.devFromQuery
  , f R "Release date"       0  FMRDate       AD.init                 AD.fromQuery
  , f R "Resolution"         0  FMResolution  AE.init                 AE.fromQuery

  , f C "Role"               1  FMRole        AS.init                 AS.roleFromQuery
  , f C "Age"                0  FMAge         AR.ageInit              AR.ageFromQuery
  , f C "Sex"                2  FMSexChar     AS.init                 (AS.sexFromQuery AS.SexChar)
  , f C "Sex (spoiler)"      0  FMSexSpoil    AS.init                 (AS.sexFromQuery AS.SexSpoil)
  , f C "Traits"             3  FMTrait       AI.init                 (AI.fromQuery -1)
  , f C ""                   0  FMTrait       AI.init                 (AI.fromQuery 0)
  , f C ""                   0  FMTrait       AI.init                 (AI.fromQuery 1)
  , f C ""                   0  FMTrait       AI.init                 (AI.fromQuery 2)
  , f C "Blood type"         0  FMBlood       AS.init                 AS.bloodFromQuery
  , f C "Height"             0  FMHeight      AR.heightInit           AR.heightFromQuery
  , f C "Weight"             0  FMWeight      AR.weightInit           AR.weightFromQuery
  , f C "Bust"               0  FMBust        AR.bustInit             AR.bustFromQuery
  , f C "Waist"              0  FMWaist       AR.waistInit            AR.waistFromQuery
  , f C "Hips"               0  FMHips        AR.hipsInit             AR.hipsFromQuery
  , f C "Cup size"           0  FMCup         AR.cupInit              AR.cupFromQuery
  ]


fieldUpdate : Data -> FieldMsg -> Field -> (Data, Field, Cmd FieldMsg)
fieldUpdate dat msg_ (num, dd, model) =
  let maps f m = (dat, (num, dd, f m), Cmd.none)              -- Simple version: update function returns a Model
      mapf fm fc (d,m,c) = (d, (num, dd, fm m), Cmd.map fc c) -- Full version: update function returns (Data, Model, Cmd)
      mapc fm fc (d,m,c) = (d, (num, DD.toggle dd False, fm m), Cmd.map fc c) -- Full version that also closes the DD (Ugly hack...)
      noop = (dat, (num, dd, model), Cmd.none)

      -- Called when opening a dropdown, can be used to focus an input element
      focus =
        case model of
          FMTag        m -> Cmd.map FSTag       (A.refocus m.conf)
          FMTrait      m -> Cmd.map FSTrait     (A.refocus m.conf)
          FMDeveloper  m -> Cmd.map FSDeveloper (A.refocus m.conf)
          FMResolution m -> Cmd.none -- TODO: Focus input field
          _ -> Cmd.none
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

      (FSNest (NAnd a b), FMNest m)  -> mapc FMNest FSNest (nestUpdate dat (NAnd a b) m)
      (FSNest (NNeg a b), FMNest m)  -> mapc FMNest FSNest (nestUpdate dat (NNeg a b) m)
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
      (FSResolution msg,FMResolution m)->maps FMResolution (AE.update msg m)
      (FSTag msg,      FMTag m)      -> mapf FMTag FSTag     (AG.update dat msg m)
      (FSTrait msg,    FMTrait m)    -> mapf FMTrait FSTrait (AI.update dat msg m)
      (FToggle b, _) -> (dat, (num, DD.toggle dd b, model), if b then focus else Cmd.none)
      _ -> noop


fieldViewDd : Data -> DD.Config FieldMsg -> Html FieldMsg -> (() -> List (Html FieldMsg)) -> Html FieldMsg
fieldViewDd dat dd lbl cont =
  div [ class "elm_dd_input" ]
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

fieldView : Data -> Field -> Html FieldMsg
fieldView dat (_, dd, model) =
  let f wrap (lbl,cont) = fieldViewDd dat dd (Html.map wrap lbl) <| \() -> List.map (Html.map wrap) (cont ())
  in case model of
      FMCustom m     -> f FSCustom     (text "Unrecognized query", \() -> [text ""]) -- TODO: Display the Query
      FMLang  m      -> f FSLang       (AS.langView False m)
      FMOLang m      -> f FSOLang      (AS.langView True  m)
      FMPlatform m   -> f FSPlatform   (AS.platformView m)
      FMLength m     -> f FSLength     (AS.lengthView m)
      FMRole m       -> f FSRole       (AS.roleView m)
      FMBlood m      -> f FSBlood      (AS.bloodView m)
      FMSexChar m    -> f FSSexChar    (AS.sexView AS.SexChar m)
      FMSexSpoil m   -> f FSSexSpoil   (AS.sexView AS.SexSpoil m)
      FMHeight m     -> f FSHeight     (AR.heightView m)
      FMWeight m     -> f FSWeight     (AR.weightView m)
      FMBust m       -> f FSBust       (AR.bustView m)
      FMWaist m      -> f FSWaist      (AR.waistView m)
      FMHips m       -> f FSHips       (AR.hipsView m)
      FMCup m        -> f FSCup        (AR.cupView m)
      FMAge m        -> f FSAge        (AR.ageView m)
      FMPopularity m -> f FSPopularity (AR.popularityView m)
      FMRating m     -> f FSRating     (AR.ratingView m)
      FMVotecount m  -> f FSVotecount  (AR.votecountView m)
      FMDeveloper m  -> f FSDeveloper  (AP.devView dat m)
      FMRDate m      -> f FSRDate      (AD.view m)
      FMResolution m -> f FSResolution (AE.view m)
      FMTag m        -> f FSTag        (AG.view dat m)
      FMTrait m      -> f FSTrait      (AI.view dat m)
      FMNest m       -> nestView dat dd m


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
    FMResolution m-> AE.toQuery m
    FMTag m      -> AG.toQuery m
    FMTrait m    -> AI.toQuery m


fieldCreate : Int -> (Data,FieldModel) -> (Data,Field)
fieldCreate fid (dat,fm) =
   ( {dat | objid = dat.objid + 1}
   , (fid, DD.init ("advsearch_field" ++ String.fromInt dat.objid) FToggle, fm)
   )


fieldInit : Int -> Data -> (Data,Field)
fieldInit n dat =
  case Array.get n fields of
    Just f -> fieldCreate n (f.init dat)
    Nothing -> fieldCreate -1 (dat, FMCustom (QAnd [])) -- Shouldn't happen.


fieldFromQuery : QType -> Data -> Query -> (Data,Field)
fieldFromQuery qtype dat q =
  let (field, _) =
        Array.foldr (\f (af,n) ->
          case (if af /= Nothing || f.qtype /= qtype then Nothing else f.fromQuery dat q) of
            Nothing -> (af,n-1)
            Just ret -> (Just (fieldCreate n ret), 0)
        ) (Nothing,Array.length fields-1) fields
  in case field of
      Just ret -> ret
      Nothing -> fieldCreate -1 (dat, FMCustom q)


fieldSub : Field -> Sub FieldMsg
fieldSub (_,dd,fm) =
  case fm of
    FMNest m ->
      Sub.batch
        <| DD.sub dd
        :: DD.sub m.addDd
        :: DD.sub m.andDd
        :: List.indexedMap (\i -> Sub.map (FSNest << NField i) << fieldSub) m.fields
    _ -> DD.sub dd
