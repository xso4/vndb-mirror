module AdvSearch.Fields exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Array
import Set
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.DropDown as DD
import Lib.Api as Api
import Lib.Autocomplete as A
import AdvSearch.Anime as AA
import AdvSearch.Set as AS
import AdvSearch.Producers as AP
import AdvSearch.Staff as AT
import AdvSearch.Tags as AG
import AdvSearch.Traits as AI
import AdvSearch.RDate as AD
import AdvSearch.Range as AR
import AdvSearch.Resolution as AE
import AdvSearch.Engine as AEng
import AdvSearch.Birthday as AB
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
  , addtype : List QType
  , neg     : Bool -- only if ptype /= qtype
  }


type NestMsg
  = NAndToggle Bool
  | NAnd Bool Bool
  | NAddToggle Bool
  | NAdd Int
  | NAddType (List QType)
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
    , addtype = [qtype]
    , neg     = False
    }
  )


nestUpdate : Data -> NestMsg -> NestModel -> (Data, NestModel, Cmd NestMsg)
nestUpdate dat msg model =
  case msg of
    NAndToggle b -> (dat, { model | andDd = DD.toggle model.andDd b, addtype = [model.qtype] }, Cmd.none)
    NAnd b _ -> (dat, { model | and = b, andDd = DD.toggle model.andDd False }, Cmd.none)
    NAddToggle b -> (dat, { model | addDd = DD.toggle model.addDd b, addtype = [model.qtype] }, Cmd.none)
    NAdd n ->
      let addPar lst (ndat,f) =
            case lst of
              (a::b::xs) ->
                -- Don't add the child field if it's an And/Or, the parent field covers that already.
                let nf = case f of
                          (_,_,FMNest m) -> if m.ptype == m.qtype then [] else [f]
                          _ -> [f]
                in addPar (b::xs) (nestInit True b a nf ndat |> Tuple.mapSecond FMNest |> fieldCreate -1)
              _ -> (ndat,f)
          (ndat2,f2) = addPar model.addtype (fieldInit n dat)
      in (ndat2, { model | addDd = DD.toggle model.addDd False, addtype = [model.qtype], fields = model.fields ++ [f2] }, Cmd.none)
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


nestToQuery : Data -> NestModel -> Maybe Query
nestToQuery dat model =
  let op  = if model.neg then Ne   else Eq
      com = if model.and then QAnd else QOr
      wrap f =
        case List.filterMap (fieldToQuery dat) model.fields of
          []  -> Nothing
          [x] -> Just (f x)
          xs  -> Just (f (com xs))
  in case (model.ptype, model.qtype) of
      (V,  R) -> wrap (QQuery 50 op)
      (V,  C) -> wrap (QQuery 51 op)
      (V,  S) -> wrap (QQuery 52 op)
      (V,  P) -> wrap (QQuery 55 op)
      (C,  S) -> wrap (QQuery 52 op)
      (C,  V) -> wrap (QQuery 53 op)
      (R,  V) -> wrap (QQuery 53 op)
      (R,  P) -> wrap (QQuery 55 op)
      _       -> wrap identity


nestFromQuery : QType -> QType -> Data -> Query -> Maybe (Data, NestModel)
nestFromQuery ptype qtype dat q =
  let init and l =
        let (ndat,fl) = List.foldr (\f (d,a) -> let (nd,fm) = fieldFromQuery qtype d f in (nd,(fm::a))) (dat,[]) l
        in nestInit and ptype qtype fl ndat

      initSub op val = if op /= Eq && op /= Ne then Nothing else Just <|
        let (ndat,f) = fieldFromQuery qtype dat val
            (ndat2,m) = nestInit True ptype qtype [f] ndat
            -- If there is only a single nested query and it's an and/or nest, merge it into this node.
            m2 = case m.fields of
                  [(_,_,FMNest cm)] -> if cm.ptype == cm.qtype then { m | fields = cm.fields, and = cm.and } else m
                  _ -> m
        in (ndat2, { m2 | neg = op == Ne })

  in case (ptype, qtype, q) of
       (V, R, QQuery 50 op r) -> initSub op r
       (V, C, QQuery 51 op r) -> initSub op r
       (V, S, QQuery 52 op r) -> initSub op r
       (V, P, QQuery 55 op r) -> initSub op r
       (C, S, QQuery 52 op r) -> initSub op r
       (C, V, QQuery 53 op r) -> initSub op r
       (R, V, QQuery 53 op r) -> initSub op r
       (R, P, QQuery 55 op r) -> initSub op r
       (_, _, QAnd l) -> if ptype == qtype then Just (init True  l) else Nothing
       (_, _, QOr  l) -> if ptype == qtype then Just (init False l) else Nothing
       _ -> Nothing


nestView : Data -> DD.Config FieldMsg -> NestModel -> Html FieldMsg
nestView dat dd model =
  let
    isNest (_,_,f) =
     case f of
       FMNest _ -> True
       _ -> False
    hasNest = List.any isNest model.fields
    filterDat =
      { dat
      | level = if model.ptype /= model.qtype then 1 else dat.level+1
      , parentTypes = if model.ptype /= model.qtype then Set.insert (showQType model.ptype) dat.parentTypes else dat.parentTypes
      }
    filters = List.indexedMap (\i f ->
        Html.map (FSNest << NField i) <| fieldView filterDat f
      ) model.fields

    add =
      let parents = Set.union filterDat.parentTypes <| Set.fromList <| List.map showQType <| List.drop 1 model.addtype
          lst = Array.toIndexedList fields |> List.filter (\(_,f) ->
                     Just f.ptype == List.head model.addtype
                  && f.title /= ""
                  && (dat.uid /= Nothing || f.title /= "My Labels")
                  && (dat.uid /= Nothing || f.title /= "My List")
                  && (f.title /= "Name" || not (Set.isEmpty parents))
                  && not (f.title == "Role" && (List.head (List.drop 1 model.addtype)) == Just C) -- No "role" filter for character seiyuu (the seiyuu role is implied, after all)
                  && not (Set.member (showQType f.qtype) parents))
          showT par t =
            case (par,t) of
              (_,V) -> "VN"
              (_,R) -> "Release"
              (_,C) -> "Character"
              (C,S) -> "VA"
              (_,S) -> "Staff"
              (V,P) -> "Developer"
              (_,P) -> "Producer"
          breads pre par l =
            case l of
              [] -> []
              [x] -> [ b [] [ text (showT par x) ] ]
              (x::xs) -> a [ href "#", onClickD (FSNest (NAddType (x::pre))) ] [ text (showT par x) ] :: text " » " :: breads (x::pre) x xs
      in
      div [ class "elm_dd_input elm_dd_noarrow short" ]
      [ DD.view model.addDd Api.Normal (text "+") <| \() ->
        [ div [ class "advheader", style "min-width" "200px" ]
          [ h3 [] [ text "Add filter" ]
          , if List.length model.addtype <= 1 then text "" else
            div [] <| breads [] model.qtype (List.reverse model.addtype)
          ]
        , ul (if List.length lst > 6 then [ style "columns" "2" ] else []) <|
              List.map (\(n,f) ->
                li [] [ a [ href "#", onClickD (FSNest <| if f.qtype /= f.ptype then NAddType (f.qtype :: model.addtype) else NAdd n)] [ text f.title ] ]
              ) lst
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
            case (model.ptype, model.qtype) of
              (_, C) -> ("Has a character that matches these filters", "Does not have a character that matches these filters")
              (_, R) -> ("Has a release that matches these filters", "Does not have a release that matches these filters")
              (_, V) -> ("Linked to a visual novel that matches these filters", "Not linked to a visual novel that matches these filters")
              (V, S) -> ("Has staff that matches these filters", "Does not have staff that matches these filters")
              (V, P) -> ("Has a developer that matches these filters", "Does not have a developer that matches these filters")
              (C, S) -> ("Has a voice actor that matches these filters", "Does not have a voice actor that matches these filters")
              (R, P) -> ("Has a producer that matches these filters", "Does not have a producer that matches these filters")
              _ -> ("","")
      in [ ul []
        [ li [] [ linkRadio (not model.neg) (FSNest << NNeg False) [ text a ] ]
        , li [] [ linkRadio (    model.neg) (FSNest << NNeg True ) [ text b ] ]
        ] ]

    neglbl = text <| (if model.neg then "¬" else "") ++
      case (model.ptype, model.qtype) of
        (_, C) -> "Char"
        (_, R) -> "Rel"
        (_, V) -> "VN"
        (V, S) -> "Staff"
        (V, P) -> "Developer"
        (R, P) -> "Producer"
        (C, S) -> "VA"
        _ -> ""

    ourdd =
      if model.qtype == model.ptype
      then fieldViewDd dat dd andlbl andcont
      else fieldViewDd dat dd neglbl negcont

    initialdd = if model.ptype == model.qtype || List.length model.fields == 1 then [ ourdd ] else [ ourdd, and ]

  in
    if hasNest
    then table [ class "advnest" ] <| List.indexedMap (\i f -> tr []
          [ td [] <| if i == 0 then initialdd else []
          , td [ class (if i == 0 then "start" else "mid") ] [ div [] [], span [] [] ]
          , td [] [ f ]
          ]) filters
          ++ [ tr []
               [ td [] []
               , td [ class "end" ] [ div [] [], span [] [] ]
               , td [] [ add ]
               ]
             ]
    else table [ class "advrow" ] [ tr []
         [ td [] (initialdd ++ [b [ class "grayedout" ] [ text " → " ]])
         , td [] (filters ++ [add]) ] ]





-- Generic field abstraction.
-- (this is where typeclasses would have been *awesome*)
--
-- The following functions and definitions are only intended to provide field
-- listings and function dispatchers, if the implementation of anything in here
-- is longer than a single line, it should get its own definition near where
-- the rest of that field is defined.

type alias Field = (Int, DD.Config FieldMsg, FieldModel) -- The Int is the index into 'fields'

type alias ListModel =
  { val : Int
  , lst : List (Query, String)
  }

type FieldModel
  = FMCustom     Query -- A read-only placeholder for Query values that failed to parse into a Field
  | FMNest       NestModel
  | FMList       ListModel
  | FMLang       AS.LangModel
  | FMRPlatform  (AS.Model String)
  | FMVPlatform  (AS.Model String)
  | FMLength     (AS.Model Int)
  | FMDevStatus  (AS.Model Int)
  | FMRole       (AS.Model String)
  | FMBlood      (AS.Model String)
  | FMSex        (AS.SexModel)
  | FMGender     (AS.Model String)
  | FMMedium     (AS.Model String)
  | FMVoiced     (AS.Model Int)
  | FMAniEro     (AS.Model Int)
  | FMAniStory   (AS.Model Int)
  | FMRType      (AS.Model String)
  | FMLabel      (AS.Model Int)
  | FMRList      (AS.Model Int)
  | FMSRole      (AS.Model String)
  | FMPType      (AS.Model String)
  | FMExtLinks   (AS.Model String)
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
  | FMMinAge     (AR.Model Int)
  | FMProdId     AP.Model
  | FMProducer   AP.Model
  | FMDeveloper  AP.Model
  | FMStaff      AT.Model
  | FMAnime      AA.Model
  | FMRDate      AD.Model
  | FMResolution AE.Model
  | FMEngine     AEng.Model
  | FMTag        AG.Model
  | FMTrait      AI.Model
  | FMBirthday   AB.Model

type FieldMsg
  = FSCustom     () -- Not actually used at the moment
  | FSNest       NestMsg
  | FSList       Int
  | FSLang       (AS.Msg String)
  | FSRPlatform  (AS.Msg String)
  | FSVPlatform  (AS.Msg String)
  | FSLength     (AS.Msg Int)
  | FSDevStatus  (AS.Msg Int)
  | FSRole       (AS.Msg String)
  | FSBlood      (AS.Msg String)
  | FSSex        AS.SexMsg
  | FSGender     (AS.Msg String)
  | FSMedium     (AS.Msg String)
  | FSVoiced     (AS.Msg Int)
  | FSAniEro     (AS.Msg Int)
  | FSAniStory   (AS.Msg Int)
  | FSRType      (AS.Msg String)
  | FSLabel      (AS.Msg Int)
  | FSRList      (AS.Msg Int)
  | FSSRole      (AS.Msg String)
  | FSPType      (AS.Msg String)
  | FSExtLinks   (AS.Msg String)
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
  | FSMinAge     AR.Msg
  | FSProdId     AP.Msg
  | FSProducer   AP.Msg
  | FSDeveloper  AP.Msg
  | FSStaff      AT.Msg
  | FSAnime      AA.Msg
  | FSRDate      AD.Msg
  | FSResolution AE.Msg
  | FSEngine     AEng.Msg
  | FSTag        AG.Msg
  | FSTrait      AI.Msg
  | FSBirthday   AB.Msg
  | FToggle Bool
  | FDel       -- intercepted in nestUpdate
  | FMoveSub   -- intercepted in nestUpdate
  | FMovePar

type alias FieldDesc =
  { qtype     : QType
  , ptype     : QType
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
        , ptype     = qtype
        , title     = title
        , quick     = quick
        , init      = \d -> (Tuple.mapSecond wrap (init d))
        , fromQuery = \d q -> Maybe.map (Tuple.mapSecond wrap) (fromq d q)
        }
      -- List type queries are fully defined here for convenience
      l qtype title quick lst =
        f qtype title quick FMList (\d -> (d, { val = 0, lst = lst }))
          (\d q -> List.indexedMap (\i (k,v) -> (i,k,v)) lst |> List.filter (\(i,k,_) -> k == q) |> List.head |> Maybe.map (\(i,_,_) -> (d, { val = i, lst = lst })))
      -- Nested queries
      n ptype qtype title =
        { qtype     = qtype
        , ptype     = ptype
        , title     = title
        , quick     = 0
        , init      = nestInit True ptype qtype [] >> Tuple.mapSecond FMNest
        , fromQuery = \d -> nestFromQuery ptype qtype d >> Maybe.map (Tuple.mapSecond FMNest)
        }
  in Array.fromList
  -- IMPORTANT: This list is processed in reverse order when reading a Query
  -- into Fields, so "catch all" fields must be listed first. In particular,
  -- FMNest with qtype == ptype go before everything else.

  --  T TITLE            QUICK  WRAP          INIT                    FROM_QUERY
  [ n V V "And/Or"
  , n V R "Release »"
  , n V S "Staff »"
  , n V C "Character »"
  , n V P "Developer »"
  , f V "Language"           1  FMLang       (AS.langInit AS.LangVN)  (AS.langFromQuery AS.LangVN)
  , f V "Original language"  2  FMLang       (AS.langInit AS.LangVNO) (AS.langFromQuery AS.LangVNO)
  , f V "Platform"           3  FMVPlatform   AS.init                 AS.platformFromQuery
  , f V "Tags"               4  FMTag         AG.init                 (AG.fromQuery -1 True)
  , f V ""                  -4  FMTag         AG.init                 (AG.fromQuery 0 True)
  , f V ""                  -4  FMTag         AG.init                 (AG.fromQuery 1 True)
  , f V ""                  -4  FMTag         AG.init                 (AG.fromQuery 2 True)
  , f V ""                  -4  FMTag         AG.init                 (AG.fromQuery 0 False)
  , f V ""                  -4  FMTag         AG.init                 (AG.fromQuery 1 False)
  , f V ""                  -4  FMTag         AG.init                 (AG.fromQuery 2 False)
  , f V "My Labels"          0  FMLabel       AS.init                 AS.labelFromQuery
  , l V "My List"            0 [(QInt 65 Eq 1, "On my list"),         (QInt 65 Ne 1, "Not on my list")]
  , f V "Length"             0  FMLength      AS.init                 AS.lengthFromQuery
  , f V "Development status" 0  FMDevStatus   AS.init                 AS.devStatusFromQuery
  , f V "Release date"       0  FMRDate       AD.init                 AD.fromQuery
  , f V "Popularity"         0  FMPopularity  AR.popularityInit       AR.popularityFromQuery
  , f V "Rating"             0  FMRating      AR.ratingInit           AR.ratingFromQuery
  , f V "Number of votes"    0  FMVotecount   AR.votecountInit        AR.votecountFromQuery
  , f V "Anime"              0  FMAnime       AA.init                 AA.fromQuery
  , l V "Has description"    0 [(QInt 61 Eq 1, "Has description"),    (QInt 61 Ne 1, "No description")]
  , l V "Has anime"          0 [(QInt 62 Eq 1, "Has anime relation"), (QInt 62 Ne 1, "No anime relation")]
  , l V "Has screenshot"     0 [(QInt 63 Eq 1, "Has screenshot(s)"),  (QInt 63 Ne 1, "No screenshot(s)")]
  , l V "Has review"         0 [(QInt 64 Eq 1, "Has review(s)"),      (QInt 64 Ne 1, "No review(s)")]
  -- Deprecated
  , f V ""                   0  FMDeveloper   AP.init                 (AP.fromQuery 6)

  , n R R "And/Or"
  , n R V "Visual Novel »"
  , n R P "Producer »"
  , f R "Language"           1  FMLang       (AS.langInit AS.LangRel) (AS.langFromQuery AS.LangRel)
  , f R "Platform"           2  FMRPlatform   AS.init                 AS.platformFromQuery
  , f R "Type"               3  FMRType       AS.init                 AS.rtypeFromQuery
  , l R "Patch"              0 [(QInt 61 Eq 1, "Patch to another release"),(QInt 61 Ne 1, "Standalone release")]
  , l R "Freeware"           0 [(QInt 62 Eq 1, "Freeware"),                (QInt 62 Ne 1, "Non-free")]
  , l R "Erotic scenes"      0 [(QInt 66 Eq 1, "Has erotic scenes"),       (QInt 66 Ne 1, "No erotic scenes")]
  , l R "Uncensored"         0 [(QInt 64 Eq 1, "Uncensored (no mosaic)"),  (QInt 64 Ne 1, "Censored (or no erotic content to censor)")]
  , l R "Official"           0 [(QInt 65 Eq 1, "Official"),                (QInt 65 Ne 1, "Unofficial")]
  , f R "Release date"       0  FMRDate       AD.init                 AD.fromQuery
  , f R "Resolution"         0  FMResolution  AE.init                 AE.fromQuery
  , f R "Age rating"         0  FMMinAge      AR.minageInit           AR.minageFromQuery
  , f R "Medium"             0  FMMedium      AS.init                 AS.mediumFromQuery
  , f R "Voiced"             0  FMVoiced      AS.init                 AS.voicedFromQuery
  , f R "Ero animation"      0  FMAniEro      AS.init                 (AS.animatedFromQuery False)
  , f R "Story animation"    0  FMAniStory    AS.init                 (AS.animatedFromQuery True)
  , f R "Engine"             0  FMEngine      AEng.init               AEng.fromQuery
  , f R "External links"     0  FMExtLinks    AS.init                 AS.extlinkFromQuery
  , f R "My List"            0  FMRList       AS.init                 AS.rlistFromQuery
  -- Deprecated
  , f R ""                   0  FMDeveloper   AP.init                 (AP.fromQuery 6)
  , f R ""                   0  FMProducer    AP.init                 (AP.fromQuery 17)


  , n C C "And/Or"
  , n C S "Voice Actor »"
  , n C V "Visual Novel »"
  , f C "Role"               1  FMRole        AS.init                 AS.roleFromQuery
  , f C "Age"                0  FMAge         AR.ageInit              AR.ageFromQuery
  , f C "Birthday"           0  FMBirthday    AB.init                 AB.fromQuery
  , f C "Sex"                2  FMSex         (AS.sexInit False)      (AS.sexFromQuery False)
  , f C ""                   0  FMSex         (AS.sexInit True)       (AS.sexFromQuery True)
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

  , n S S "And/Or"
  , f S "Name"               0  FMStaff       AT.init                 AT.fromQuery
  , f S "Language"           1  FMLang        (AS.langInit AS.LangStaff) (AS.langFromQuery AS.LangStaff)
  , f S "Gender"             2  FMGender      AS.init                 AS.genderFromQuery
  , f S "Role"               3  FMSRole       AS.init                 AS.sroleFromQuery

  , n P P "And/Or"
  , f P "Name"               0  FMProdId      AP.init                 (AP.fromQuery 3)
  , f P "Language"           1  FMLang        (AS.langInit AS.LangProd) (AS.langFromQuery AS.LangProd)
  , f P "Type"               2  FMPType       AS.init                 AS.ptypeFromQuery
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
          FMTag        m -> Cmd.map FSTag        (A.refocus m.conf)
          FMTrait      m -> Cmd.map FSTrait      (A.refocus m.conf)
          FMProdId     m -> Cmd.map FSProdId     (A.refocus m.conf)
          FMProducer   m -> Cmd.map FSProducer   (A.refocus m.conf)
          FMDeveloper  m -> Cmd.map FSDeveloper  (A.refocus m.conf)
          FMStaff      m -> Cmd.map FSStaff      (A.refocus m.conf)
          FMAnime      m -> Cmd.map FSAnime      (A.refocus m.conf)
          FMResolution m -> Cmd.map FSResolution (A.refocus m.conf)
          FMEngine     m -> Cmd.map FSEngine     (A.refocus m.conf)
          _ -> Cmd.none
  in case (msg_, model) of
      -- Move to parent node is tricky, needs to be intercepted at this point so that we can access the parent NestModel.
      (FSNest (NField parentNum (FSNest (NField fieldNum FMovePar))), FMNest grandModel) ->
        case List.head <| List.drop parentNum grandModel.fields of
          Just (_,_,FMNest parentModel) ->
            let fieldField = List.drop fieldNum parentModel.fields |> List.take 1
                newFields = List.map (\(fid,fdd,fm) -> (fid, DD.toggle fdd False, fm)) fieldField
                newParentModel = { parentModel | fields = delidx fieldNum parentModel.fields }
                addGrandFields = List.take parentNum grandModel.fields ++ newFields ++ List.drop parentNum grandModel.fields
                newGrandFields =
                  if List.isEmpty newParentModel.fields
                  then delidx (parentNum+1) addGrandFields
                  else modidx (parentNum+1) (\(pid,pdd,_) -> (pid,pdd,FMNest newParentModel)) addGrandFields
                newGrandModel = { grandModel | fields = newGrandFields }
            in (dat, (num,dd,FMNest newGrandModel), Cmd.none)
          _ -> noop

      -- Move root node to sub; for child nodes this is handled in nestUpdate, but the root node must be handled separately
      (FMoveSub, FMNest m) ->
        let subfields = [(num,DD.toggle dd False,model)]
            (ndat,subm) = nestInit True m.qtype m.qtype subfields dat
            (ndat2,subf) = fieldCreate -1 (ndat, FMNest subm)
        in (ndat2, subf, Cmd.none)

      (FSNest (NAnd a b), FMNest m)  -> mapc FMNest FSNest (nestUpdate dat (NAnd a b) m)
      (FSNest (NNeg a b), FMNest m)  -> mapc FMNest FSNest (nestUpdate dat (NNeg a b) m)
      (FSNest msg,     FMNest m)     -> mapf FMNest FSNest (nestUpdate dat msg m)
      (FSList msg,     FMList m)     -> (dat, (num,DD.toggle dd False,FMList { m | val = msg }), Cmd.none)
      (FSLang msg,     FMLang m)     -> maps FMLang     (AS.langUpdate msg m)
      (FSRPlatform msg,FMRPlatform m)-> maps FMRPlatform(AS.update msg m)
      (FSVPlatform msg,FMVPlatform m)-> maps FMVPlatform(AS.update msg m)
      (FSLength msg,   FMLength m)   -> maps FMLength   (AS.update msg m)
      (FSDevStatus msg,FMDevStatus m)-> maps FMDevStatus(AS.update msg m)
      (FSRole msg,     FMRole m)     -> maps FMRole     (AS.update msg m)
      (FSBlood msg,    FMBlood m)    -> maps FMBlood    (AS.update msg m)
      (FSSex msg,      FMSex m)      -> maps FMSex      (AS.sexUpdate msg m)
      (FSGender msg,   FMGender m)   -> maps FMGender   (AS.update msg m)
      (FSMedium msg,   FMMedium m)   -> maps FMMedium   (AS.update msg m)
      (FSVoiced msg,   FMVoiced m)   -> maps FMVoiced   (AS.update msg m)
      (FSAniEro msg,   FMAniEro m)   -> maps FMAniEro   (AS.update msg m)
      (FSAniStory msg, FMAniStory m) -> maps FMAniStory (AS.update msg m)
      (FSRType  msg,   FMRType m)    -> maps FMRType    (AS.update msg m)
      (FSLabel  msg,   FMLabel m)    -> maps FMLabel    (AS.update msg m)
      (FSRList  msg,   FMRList m)    -> maps FMRList    (AS.update msg m)
      (FSSRole  msg,   FMSRole m)    -> maps FMSRole    (AS.update msg m)
      (FSPType  msg,   FMPType m)    -> maps FMPType    (AS.update msg m)
      (FSExtLinks msg ,FMExtLinks m) -> maps FMExtLinks (AS.update msg m)
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
      (FSMinAge msg   ,FMMinAge m)   -> maps FMMinAge   (AR.update msg m)
      (FSProdId   msg, FMProdId m)   -> mapf FMProdId    FSProdId    (AP.update dat msg m)
      (FSProducer msg, FMProducer m) -> mapf FMProducer  FSProducer  (AP.update dat msg m)
      (FSDeveloper msg,FMDeveloper m)-> mapf FMDeveloper FSDeveloper (AP.update dat msg m)
      (FSStaff msg,    FMStaff m)    -> mapf FMStaff     FSStaff     (AT.update dat msg m)
      (FSAnime msg,    FMAnime m)    -> mapf FMAnime     FSAnime     (AA.update dat msg m)
      (FSRDate msg,    FMRDate m)    -> maps FMRDate    (AD.update msg m)
      (FSResolution msg,FMResolution m)->mapf FMResolution FSResolution (AE.update dat msg m)
      (FSEngine msg,   FMEngine m)   -> mapf FMEngine FSEngine (AEng.update dat msg m)
      (FSTag msg,      FMTag m)      -> mapf FMTag FSTag     (AG.update dat msg m)
      (FSTrait msg,    FMTrait m)    -> mapf FMTrait FSTrait (AI.update dat msg m)
      (FSBirthday msg, FMBirthday m) -> maps FMBirthday (AB.update msg m)
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
      , a [ href "#", onClickD FMoveSub, title "Create new branch for this filter" ] [ text "↳" ]
      ] :: cont ()
  ]

fieldView : Data -> Field -> Html FieldMsg
fieldView dat (_, dd, model) =
  let f wrap (lbl,cont) = fieldViewDd dat dd (Html.map wrap lbl) <| \() -> List.map (Html.map wrap) (cont ())
      l m = ( span [ class "nowrap" ] [ text <| Maybe.withDefault "" <| Maybe.map Tuple.second <| List.head <| List.drop m.val m.lst ]
            , \() -> [ ul [] <| List.indexedMap (\n (_,v) -> li [] [ linkRadio (n == m.val) (\_ -> n) [ text v ] ]) m.lst ]
            )
  in case model of
      FMCustom m     -> f FSCustom     (text "Unrecognized query", \() -> [text ""]) -- TODO: Display the Query
      FMList m       -> f FSList       (l m)
      FMLang  m      -> f FSLang       (AS.langView m)
      FMVPlatform m  -> f FSVPlatform  (AS.platformView False m)
      FMRPlatform m  -> f FSRPlatform  (AS.platformView True m)
      FMLength m     -> f FSLength     (AS.lengthView m)
      FMDevStatus m  -> f FSDevStatus  (AS.devStatusView m)
      FMRole m       -> f FSRole       (AS.roleView m)
      FMBlood m      -> f FSBlood      (AS.bloodView m)
      FMSex m        -> f FSSex        (AS.sexView m)
      FMGender m     -> f FSGender     (AS.genderView m)
      FMMedium m     -> f FSMedium     (AS.mediumView m)
      FMVoiced m     -> f FSVoiced     (AS.voicedView m)
      FMAniEro m     -> f FSAniEro     (AS.animatedView False m)
      FMAniStory m   -> f FSAniStory   (AS.animatedView True m)
      FMRType m      -> f FSRType      (AS.rtypeView m)
      FMLabel m      -> f FSLabel      (AS.labelView dat m)
      FMRList m      -> f FSRList      (AS.rlistView m)
      FMSRole m      -> f FSSRole      (AS.sroleView m)
      FMPType m      -> f FSPType      (AS.ptypeView m)
      FMExtLinks m   -> f FSExtLinks   (AS.extlinkView m)
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
      FMMinAge m     -> f FSMinAge     (AR.minageView m)
      FMProdId m     -> f FSProdId     (AP.view "Name" dat m)
      FMProducer m   -> f FSProducer   (AP.view "Producer" dat m)
      FMDeveloper m  -> f FSDeveloper  (AP.view "Developer" dat m)
      FMStaff m      -> f FSStaff      (AT.view dat m)
      FMAnime m      -> f FSAnime      (AA.view dat m)
      FMRDate m      -> f FSRDate      (AD.view m)
      FMResolution m -> f FSResolution (AE.view m)
      FMEngine m     -> f FSEngine     (AEng.view m)
      FMTag m        -> f FSTag        (AG.view dat m)
      FMTrait m      -> f FSTrait      (AI.view dat m)
      FMBirthday m   -> f FSBirthday   (AB.view m)
      FMNest m       -> nestView dat dd m


fieldToQuery : Data -> Field -> Maybe Query
fieldToQuery dat (_, _, model) =
  case model of
    FMCustom m   -> Just m
    FMList m     -> List.drop m.val m.lst |> List.head |> Maybe.map Tuple.first
    FMNest m     -> nestToQuery dat m
    FMLang m     -> AS.langToQuery m
    FMRPlatform m-> AS.toQuery (QStr 4) m
    FMVPlatform m-> AS.toQuery (QStr 4) m
    FMLength m   -> AS.toQuery (QInt 5) m
    FMDevStatus m-> AS.toQuery (QInt 66) m
    FMRole m     -> AS.toQuery (QStr 2) m
    FMBlood m    -> AS.toQuery (QStr 3) m
    FMSex (s,m)  -> AS.toQuery (QStr (if s then 5 else 4)) m
    FMGender m   -> AS.toQuery (QStr 4) m
    FMMedium m   -> AS.toQuery (QStr 11) m
    FMVoiced m   -> AS.toQuery (QInt 12) m
    FMAniEro m   -> AS.toQuery (QInt 13) m
    FMAniStory m -> AS.toQuery (QInt 14) m
    FMRType m    -> AS.toQuery (QStr 16) m
    FMLabel m    -> AS.toQuery (\op v -> QTuple 12 op (Maybe.withDefault 0 (Maybe.map vndbidNum dat.uid)) v) m
    FMRList m    -> AS.toQuery (QInt 18) m
    FMSRole m    -> AS.toQuery (QStr 5) m
    FMPType m    -> AS.toQuery (QStr 4) m
    FMExtLinks m -> AS.toQuery (QStr 19) m
    FMHeight m   -> AR.toQuery (QInt 6) (QStr 6) m
    FMWeight m   -> AR.toQuery (QInt 7) (QStr 7) m
    FMBust m     -> AR.toQuery (QInt 8) (QStr 8) m
    FMWaist m    -> AR.toQuery (QInt 9) (QStr 9) m
    FMHips m     -> AR.toQuery (QInt 10) (QStr 10) m
    FMCup m      -> AR.toQuery (QStr 11) (QStr 11) m
    FMAge m      -> AR.toQuery (QInt 12) (QStr 12) m
    FMPopularity m->AR.toQuery (QInt 9) (QStr 9) m
    FMRating m   -> AR.toQuery (QInt 10) (QStr 10) m
    FMVotecount m-> AR.toQuery (QInt 11) (QStr 11) m
    FMMinAge m   -> AR.toQuery (QInt 10) (QStr 10) m
    FMProdId m -> AP.toQuery 3 m
    FMProducer m -> AP.toQuery 17 m
    FMDeveloper m-> AP.toQuery 6 m
    FMStaff m    -> AT.toQuery m
    FMAnime m    -> AA.toQuery m
    FMRDate m    -> AD.toQuery m
    FMResolution m-> AE.toQuery m
    FMEngine m   -> AEng.toQuery m
    FMTag m      -> AG.toQuery m
    FMTrait m    -> AI.toQuery m
    FMBirthday m -> AB.toQuery m


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
          case (if af /= Nothing || f.ptype /= qtype then Nothing else f.fromQuery dat q) of
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
