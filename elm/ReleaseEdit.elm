module ReleaseEdit exposing (main)

import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Browser.Dom as Dom
import Bitwise as B
import Set
import Task
import Process
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Lib.DropDown as DD
import Lib.Editsum as Editsum
import Lib.RDate as D
import Lib.Autocomplete as A
import Lib.ExtLinks as EL
import Gen.ReleaseEdit as GRE
import Gen.Types as GT
import Gen.Api as GApi
import Gen.ExtLinks as GEL


main : Program GRE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m -> DD.sub m.platDd
  }


type alias Model =
  { state      : Api.State
  , titles     : List GRE.RecvTitles
  , olang      : String
  , official   : Bool
  , patch      : Bool
  , freeware   : Bool
  , hasEro     : Bool
  , doujin     : Bool
  , plat       : Set.Set String
  , platDd     : DD.Config Msg
  , media      : List GRE.RecvMedia
  , gtin       : String
  , gtinValid  : Bool
  , catalog    : String
  , released   : D.RDate
  , minage     : Maybe Int
  , uncensored : Maybe Bool
  , resoX      : Int
  , resoY      : Int
  , reso       : A.Model GApi.ApiResolutions
  , voiced     : Int
  , ani_story  : Int
  , ani_ero    : Int
  , ani_story_sp : Maybe Int
  , ani_story_cg : Maybe Int
  , ani_cutscene : Maybe Int
  , ani_ero_sp : Maybe Int
  , ani_ero_cg : Maybe Int
  , ani_face   : Maybe Bool
  , ani_bg     : Maybe Bool
  , website    : String
  , engine     : A.Model GApi.ApiEngines
  , extlinks   : EL.Model GRE.RecvExtlinks
  , vn         : List GRE.RecvVn
  , vnAdd      : A.Model GApi.ApiVNResult
  , prod       : List GRE.RecvProducers
  , prodAdd    : A.Model GApi.ApiProducerResult
  , notes      : TP.Model
  , editsum    : Editsum.Model
  , id         : Maybe String
  }


init : GRE.Recv -> Model
init d =
  { state      = Api.Normal
  , titles     = d.titles
  , olang      = d.olang
  , official   = d.official
  , patch      = d.patch
  , freeware   = d.freeware
  , hasEro     = d.has_ero
  , doujin     = d.doujin
  , plat       = Set.fromList <| List.map (\e -> e.platform) d.platforms
  , platDd     = DD.init "platforms" PlatOpen
  , media      = List.map (\m -> { m | qty = if m.qty == 0 then 1 else m.qty }) d.media
  , gtin       = if d.gtin == "0" then "" else String.padLeft 12 '0' d.gtin
  , gtinValid  = True
  , catalog    = d.catalog
  , released   = d.released
  , minage     = d.minage
  , uncensored = d.uncensored
  , resoX      = d.reso_x
  , resoY      = d.reso_y
  , reso       = A.init (resoFmt True d.reso_x d.reso_y)
  , voiced     = d.voiced
  , ani_story  = d.ani_story
  , ani_ero    = d.ani_ero
  , ani_story_sp = d.ani_story_sp
  , ani_story_cg = d.ani_story_cg
  , ani_cutscene = d.ani_cutscene
  , ani_ero_sp = d.ani_ero_sp
  , ani_ero_cg = d.ani_ero_cg
  , ani_face   = d.ani_face
  , ani_bg     = d.ani_bg
  , website    = d.website
  , engine     = A.init d.engine
  , extlinks   = EL.new d.extlinks GEL.releaseSites
  , vn         = d.vn
  , vnAdd      = A.init ""
  , prod       = d.producers
  , prodAdd    = A.init ""
  , notes      = TP.bbcode d.notes
  , editsum    = { authmod = d.authmod, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden, hasawait = False }
  , id         = d.id
  }


encode : Model -> GRE.Send
encode model =
  { id          = model.id
  , editsum     = model.editsum.editsum.data
  , hidden      = model.editsum.hidden
  , locked      = model.editsum.locked
  , titles      = model.titles
  , olang       = model.olang
  , official    = model.official
  , patch       = model.patch
  , freeware    = model.freeware
  , has_ero     = model.hasEro
  , doujin      = model.doujin
  , platforms   = List.map (\l -> {platform=l}) <| Set.toList model.plat
  , media       = model.media
  , gtin        = model.gtin
  , catalog     = model.catalog
  , released    = model.released
  , minage      = model.minage
  , uncensored  = model.uncensored
  , reso_x      = model.resoX
  , reso_y      = model.resoY
  , voiced      = model.voiced
  , ani_story   = model.ani_story
  , ani_ero     = model.ani_ero
  , ani_story_sp = model.ani_story_sp
  , ani_story_cg = model.ani_story_cg
  , ani_cutscene = model.ani_cutscene
  , ani_ero_sp  = model.ani_ero_sp
  , ani_ero_cg  = model.ani_ero_cg
  , ani_face    = model.ani_face
  , ani_bg      = model.ani_bg
  , website     = model.website
  , engine      = model.engine.value
  , extlinks    = model.extlinks.links
  , vn          = List.map (\l -> {vid=l.vid, rtype=l.rtype}) model.vn
  , producers   = List.map (\l -> {pid=l.pid, developer=l.developer, publisher=l.publisher}) model.prod
  , notes       = model.notes.data
  }

vnConfig : A.Config Msg GApi.ApiVNResult
vnConfig = { wrap = VNSearch, id = "vnadd", source = A.vnSource }

producerConfig : A.Config Msg GApi.ApiProducerResult
producerConfig = { wrap = ProdSearch, id = "prodadd", source = A.producerSource }

resoConfig : A.Config Msg GApi.ApiResolutions
resoConfig = { wrap = Resolution, id = "resolution", source = A.resolutionSource }

engineConfig : A.Config Msg GApi.ApiEngines
engineConfig = { wrap = Engine, id = "engine", source = A.engineSource }


type Msg
  = Noop
  | TitleAdd String
  | TitleDel Int
  | TitleLang Int String
  | TitleTitle Int String
  | TitleLatin Int String
  | TitleMtl Int Bool
  | TitleMain String
  | Official Bool
  | Patch Bool
  | Freeware Bool
  | HasEro Bool
  | Plat String Bool
  | PlatOpen Bool
  | MediaType Int String
  | MediaQty Int Int
  | MediaDel Int
  | Gtin String
  | Catalog String
  | Released D.RDate
  | Minage (Maybe Int)
  | Uncensored (Maybe Bool)
  | Resolution (A.Msg GApi.ApiResolutions)
  | Voiced Int
  | AniStory Int
  | AniEro Int
  | AniUnknown
  | AniNoAni
  | AniStorySp (Maybe Int)
  | AniStoryCg (Maybe Int)
  | AniCutscene (Maybe Int)
  | AniEroSp (Maybe Int)
  | AniEroCg (Maybe Int)
  | AniFace (Maybe Bool)
  | AniBg (Maybe Bool)
  | Website String
  | Engine (A.Msg GApi.ApiEngines)
  | ExtLinks (EL.Msg GRE.RecvExtlinks)
  | VNRType Int String
  | VNDel Int
  | VNSearch (A.Msg GApi.ApiVNResult)
  | ProdDel Int
  | ProdRole Int (Bool, Bool)
  | ProdSearch (A.Msg GApi.ApiProducerResult)
  | Notes (TP.Msg)
  | Editsum Editsum.Msg
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Noop -> (model, Cmd.none)
    TitleAdd s ->
      ({ model | titles = model.titles ++ [{ lang = s, title = "", latin = Nothing, mtl = False }], olang = if List.isEmpty model.titles then s else model.olang }
      , Task.attempt (always Noop) (Dom.focus ("title_" ++ s)))
    TitleDel i     -> ({ model | titles = delidx i model.titles }, Cmd.none)
    TitleLang i s  -> ({ model | titles = modidx i (\e -> { e | lang = s }) model.titles }, Cmd.none)
    TitleTitle i s -> ({ model | titles = modidx i (\e -> { e | title = s }) model.titles }, Cmd.none)
    TitleLatin i s -> ({ model | titles = modidx i (\e -> { e | latin = if s == "" then Nothing else Just s }) model.titles }, Cmd.none)
    TitleMtl i s   -> ({ model | titles = modidx i (\e -> { e | mtl = s }) model.titles }, Cmd.none)
    TitleMain s    -> ({ model | olang = s }, Cmd.none)

    Official b -> ({ model | official = b }, Cmd.none)
    Patch b    -> ({ model | patch    = b }, Cmd.none)
    Freeware b -> ({ model | freeware = b }, Cmd.none)
    HasEro b   -> ({ model | hasEro   = b }, Cmd.none)
    Plat s b   -> ({ model | plat     = if b then Set.insert s model.plat else Set.remove s model.plat }, Cmd.none)
    PlatOpen b -> ({ model | platDd   = DD.toggle model.platDd b }, Cmd.none)
    MediaType n s -> ({ model | media = if s /= "unk" && n == List.length model.media then model.media ++ [{medium = s, qty = 1}] else modidx n (\m -> { m | medium = s }) model.media }, Cmd.none)
    MediaQty n i  -> ({ model | media = modidx n (\m -> { m | qty    = i }) model.media }, Cmd.none)
    MediaDel i -> ({ model | media = delidx i model.media }, Cmd.none)
    Gtin s     -> ({ model | gtin = s, gtinValid = s == "" || validateGtin s }, Cmd.none)
    Catalog s  -> ({ model | catalog = s }, Cmd.none)
    Released d -> ({ model | released = d }, Cmd.none)
    Minage i   -> ({ model | minage = i }, Cmd.none)
    Uncensored b->({ model | uncensored = b }, Cmd.none)
    Resolution m->
      let (nm, c, en) = A.update resoConfig m model.reso
          nmod = { model | reso = Maybe.withDefault nm <| Maybe.map (\e -> A.clear nm e.resolution) en }
          n2mod = case resoParse True nmod.reso.value of
            Just (x,y) -> { nmod | resoX = x, resoY = y }
            Nothing -> nmod
      in (n2mod, c)
    Voiced i   -> ({ model | voiced = i }, Cmd.none)
    AniStory i -> ({ model | ani_story = i }, Cmd.none)
    AniEro i   -> ({ model | ani_ero   = i }, Cmd.none)
    AniUnknown -> ({ model | ani_story_sp = Nothing, ani_story_cg = Nothing, ani_cutscene = Nothing
                   , ani_ero_sp = Nothing, ani_ero_cg = Nothing
                   , ani_face = Nothing, ani_bg = Nothing }, Cmd.none)
    AniNoAni   -> ({ model | ani_story_sp = Just 0,  ani_story_cg = Just 0,  ani_cutscene = Just 1
                   , ani_ero_sp = if model.minage == Just 18 then Just 1 else Nothing
                   , ani_ero_cg = if model.minage == Just 18 then Just 0 else Nothing
                   , ani_face = Just False, ani_bg = Just False }, Cmd.none)
    AniStorySp i -> ({ model | ani_story_sp = i }, Cmd.none)
    AniStoryCg i -> ({ model | ani_story_cg = i }, Cmd.none)
    AniEroSp   i -> ({ model | ani_ero_sp   = i }, Cmd.none)
    AniEroCg   i -> ({ model | ani_ero_cg   = i }, Cmd.none)
    AniCutscene i-> ({ model | ani_cutscene = i }, Cmd.none)
    AniFace b  -> ({ model | ani_face = b }, Cmd.none)
    AniBg b    -> ({ model | ani_bg = b }, Cmd.none)
    Website s  -> ({ model | website = s }, Cmd.none)
    Engine m   ->
      let (nm, c, en) = A.update engineConfig m model.engine
          nmod = case en of
            Just e  -> A.clear nm e.engine
            Nothing -> nm
      in ({ model | engine = nmod }, c)
    ExtLinks m -> ({ model | extlinks = EL.update m model.extlinks }, Cmd.none)

    VNRType i s-> ({ model | vn = modidx i (\v -> { v | rtype = s }) model.vn }, Cmd.none)
    VNDel i    -> ({ model | vn = delidx i model.vn }, Cmd.none)
    VNSearch m ->
      let (nm, c, res) = A.update vnConfig m model.vnAdd
      in case res of
        Nothing -> ({ model | vnAdd = nm }, c)
        Just v  ->
          if List.any (\vn -> vn.vid == v.id) model.vn
          then ({ model | vnAdd = nm }, c)
          else ({ model | vnAdd = A.clear nm "", vn = model.vn ++ [{ vid = v.id, title = v.title, rtype = "complete" }] }, c)

    ProdDel i   -> ({ model | prod = delidx i model.prod }, Cmd.none)
    ProdRole i (d,p) -> ({ model | prod = modidx i (\e -> { e | developer = d, publisher = p }) model.prod }, Cmd.none)
    ProdSearch m ->
      let (nm, c, res) = A.update producerConfig m model.prodAdd
      in case res of
        Nothing -> ({ model | prodAdd = nm }, c)
        Just p  ->
          if List.any (\e -> e.pid == p.id) model.prod
          then ({ model | prodAdd = nm }, c)
          else ({ model | prodAdd = A.clear nm "", prod = model.prod ++ [{ pid = p.id, name = p.name, developer = True, publisher = True}] }, c)

    Notes m    -> let (nm, nc) = TP.update m model.notes in ({ model | notes = nm }, Cmd.map Notes nc)
    Editsum m  -> let (nm,nc) = Editsum.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)

    Submit -> ({ model | state = Api.Loading }, GRE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


isValid : Model -> Bool
isValid model = not
  (  List.any (\e -> e.title /= "" && Just e.title == e.latin) model.titles
  || List.isEmpty model.titles
  || hasDuplicates (List.map (\m -> (m.medium, m.qty)) model.media)
  || not model.gtinValid
  || List.isEmpty model.vn
  || resoParse True model.reso.value == Nothing
  )


viewAnimation : Bool -> String -> (Maybe Int -> Msg) -> Maybe Int -> List (Html Msg)
viewAnimation cut na m v =
  let isset mask = mask == B.and mask (Maybe.withDefault 0 v)
      set mask b = m <| if b then Just (B.or mask (Maybe.withDefault 0 v))
                        else if Maybe.map (\x -> B.and x (4+8+16+32)) v == Just mask then Nothing
                        else Just (B.and (B.xor (B.complement 0) mask) (Maybe.withDefault 0 v))
      lbl typ txt =
        if v == Nothing || (typ == 0 && v == Just 0) || (typ == 1 && v == Just 1) || (typ == 2 && v /= Just 0 && v /= Just 1)
        then text txt
        else b [ class "grayedout" ] [ text txt ]
  in
  [ if cut then text "" else
    label [] [ inputCheck "" (v == Just 0) (\b -> m <| if b then Just 0 else Nothing), lbl 0 " Not animated", br [] [] ]
  , label [] [ inputCheck "" (v == Just 1) (\b -> m <| if b then Just 1 else Nothing), lbl 1 na ], br [] []
  , label [] [ inputCheck "" (isset  4) (set  4), lbl 2 " Hand Drawn" ], br [] []
  , label [] [ inputCheck "" (isset  8) (set  8), lbl 2 " Vectorial" ], br [] []
  , label [] [ inputCheck "" (isset 16) (set 16), lbl 2 " 3D" ], br [] []
  , label [] [ inputCheck "" (isset 32) (set 32), lbl 2 " Live action" ]
  , if cut || v == Nothing || v == Just 0 || v == Just 1 then text "" else span []
    [ br [] []
    , inputSelect ""
      (B.and (256+512) (Maybe.withDefault 0 v))
      (\i -> m (Just (B.or i (B.and (Maybe.withDefault 0 v) (B.xor (B.complement 0) (256+512))))))
      [style "width" "150px"]
      [ (0, "- frequency -"), (256, "Some scenes"), (512, "All scenes") ]
    ]
  ]

viewTitle : Model -> Int -> GRE.RecvTitles -> Html Msg
viewTitle model i e = tr []
  [ td [] [ langIcon e.lang ]
  , td []
    [ inputText ("title_"++e.lang) e.title (TitleTitle i) (style "width" "500px" :: placeholder "Title (in the original script)" :: GRE.valTitlesTitle)
    , if not (e.latin /= Nothing || containsNonLatin e.title) then text "" else span []
      [ br [] []
      , inputText "" (Maybe.withDefault "" e.latin) (TitleLatin i) (style "width" "500px" :: placeholder "Romanization" :: GRE.valTitlesLatin)
      , case e.latin of
          Just s -> if containsNonLatin s then b [ class "standout" ] [ br [] [], text "Romanization should only consist of characters in the latin alphabet." ] else text ""
          Nothing -> text ""
      ]
    , if List.length model.titles == 1 then text "" else span []
      [ br [] []
      , label [] [ inputRadio "olang" (e.lang == model.olang) (\_ -> TitleMain e.lang), text " main title" ]
      ]
    , br [] []
    , label [] [ inputCheck "" e.mtl (TitleMtl i), text " Machine translation" ]
    , if e.lang == model.olang then text "" else span []
      [ br [] [], inputButton "remove" (TitleDel i) [] ]
    , br_ 2
    ]
  ]

viewGen : Model -> Html Msg
viewGen model =
  table [ class "formtable" ] <|
  [ formField "Languages & titles"
    [ table [] <| List.indexedMap (viewTitle model) model.titles
    , inputSelect "" "" TitleAdd [] <| ("", "- Add language -") :: List.filter (\(l,_) -> l /= "zh" && not (List.any (\e -> e.lang == l) model.titles)) GT.languages
    ]

  , tr [ class "newpart" ] [ td [] [] ]
  , formField "" [ label [] [ inputCheck "" model.official Official, text " Official (i.e. sanctioned by the original developer of the visual novel)" ] ]
  , formField "" [ label [] [ inputCheck "" model.patch    Patch   , text " This release is a patch to another release.", text " (*)" ] ]
  , formField "" [ label [] [ inputCheck "" model.freeware Freeware, text " Freeware (i.e. available at no cost)" ] ]
  , formField "" [ label [] [ inputCheck "" model.hasEro   HasEro  , text " Contains erotic scenes", text " (*)" ] ]
  , formField "minage::Age rating" [ inputSelect "minage" model.minage Minage [] ((Nothing, "Unknown") :: List.map (Tuple.mapFirst Just) GT.ageRatings) ]
  , formField "Release date" [ D.view model.released False False Released, text " Leave month or day blank if they are unknown." ]

  , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Format" ] ]
  , formField "Platform(s)"
    [ div [ class "elm_dd_input", style "width" "500px" ] [ DD.view model.platDd Api.Normal
      (if Set.isEmpty model.plat
       then text "No platform selected"
       else span [] <| List.intersperse (text ", ") <| List.map (\(p,t) -> span [ style "white-space" "nowrap" ] [ platformIcon p, text t ]) <| List.filter (\(p,_) -> Set.member p model.plat) GT.platforms)
      <| \() -> [ ul [ style "columns" "2"] <| List.map (\(p,t) -> li [ classList [("separator", p == "web")] ] [ linkRadio (Set.member p model.plat) (Plat p) [ platformIcon p, text t ] ]) GT.platforms ]
    ] ]
  , formField "Media"
    [ table [] <| List.indexedMap (\i m ->
        let q = List.filter (\(s,_,_) -> m.medium == s) GT.media |> List.head |> Maybe.map (\(_,_,x) -> x) |> Maybe.withDefault False
        in tr []
            [ td [] [ inputSelect "" m.medium (MediaType i) [] <| (if m.medium == "unk" then [("unk", "- Add medium -")] else []) ++ List.map (\(a,b,_) -> (a,b)) GT.media ]
            , td [] [ if q then inputSelect "" m.qty (MediaQty i) [ style "width" "100px" ] <| List.map (\a -> (a,String.fromInt a)) <| List.range 1 40 else text "" ]
            , td [] [ if m.medium == "unk" then text "" else inputButton "remove" (MediaDel i) [] ]
            ]
      ) <| model.media ++ [{medium = "unk", qty = 0}]
    , if hasDuplicates (List.map (\m -> (m.medium, m.qty)) model.media)
      then b [ class "standout" ] [ text "List contains duplicates", br [] [] ]
      else text ""
    ]

  , if model.patch then text "" else
    formField "engine::Engine" [ A.view engineConfig model.engine [] ]
  , if model.patch then text "" else
    formField "resolution::Resolution"
    [ A.view resoConfig model.reso []
    , if resoParse True model.reso.value == Nothing then b [ class "standout" ] [ text " Invalid resolution" ] else text ""
    ]
  , if model.patch then text "" else
    formField "voiced::Voiced" [ inputSelect "voiced" model.voiced Voiced [] GT.voiced ]
  , if not model.hasEro then text "" else
    formField "uncensored::Censoring"
    [ inputSelect "uncensored" model.uncensored Uncensored []
      [ (Nothing, "Unknown")
      , (Just False, "Censored graphics")
      , (Just True, "Uncensored graphics") ]
    , text " Whether erotic graphics are censored with mosaic or other optical censoring." ]

  ] ++ (if model.patch then [] else
  [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Animation" ] ]
  , formField "Presets"
    [ a [ href "#", onClickD AniUnknown ] [ text "Unknown" ], text " | "
    , a [ href "#", onClickD AniNoAni ] [ text "No animation" ]
    ]
  , formField "Story scenes" [ table [] [ tr []
      [ td [ style "width" "170px" ] <| [ b [] [ text "Character sprites:"  ], br [] [] ] ++ viewAnimation False " No sprites" AniStorySp model.ani_story_sp
      , td [ style "width" "170px" ] <| [ b [] [ text "CGs:" ], br [] [] ] ++ viewAnimation False " No CGs" AniStoryCg model.ani_story_cg
      , td [] <| [ b [] [ text "Cutscenes:" ], br [] [] ] ++ viewAnimation True " No cutscenes" AniCutscene model.ani_cutscene
      ]
    ] ]
  , if not model.hasEro then text "" else
    formField "Erotic scenes" [ table [] [ tr []
      [ td [ style "width" "170px" ] <| [ b [] [ text "Character sprites:"  ], br [] [] ] ++ viewAnimation False " No sprites" AniEroSp model.ani_ero_sp
      , td [] <| [ b [] [ text "CGs:" ], br [] [] ] ++ viewAnimation False " No CGs" AniEroCg model.ani_ero_cg
      ]
    ] ]
  , formField "Effects" [ table []
    [ tr []
      [ td [] [ text "Character lip movement and/or eye blink: " ]
      , td []
        [ label [] [ inputRadio "ani_face" (model.ani_face == Nothing) (always (AniFace Nothing)), text " Unknown or N/A" ], text " / "
        , label [] [ inputRadio "ani_face" (model.ani_face == Just False) (always (AniFace (Just False))), text " No" ], text " / "
        , label [] [ inputRadio "ani_face" (model.ani_face == Just True) (always (AniFace (Just True))), text " Yes" ]
        ]
      ]
    , tr []
      [ td [] [ text "Background effects: " ]
      , td []
        [ label [] [ inputRadio "ani_bg" (model.ani_bg == Nothing) (always (AniBg Nothing)), text " Unknown or N/A" ], text " / "
        , label [] [ inputRadio "ani_bg" (model.ani_bg == Just False) (always (AniBg (Just False))), text " No" ], text " / "
        , label [] [ inputRadio "ani_bg" (model.ani_bg == Just True) (always (AniBg (Just True))), text " Yes" ]
        ]
      ]
    ] ]

  ]) ++
  [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "External identifiers & links" ] ]
  , formField "gtin::JAN/UPC/EAN"
    [ inputText "gtin" model.gtin Gtin [pattern "[0-9]+"]
    , if not model.gtinValid then b [ class "standout" ] [ text "Invalid GTIN code" ] else text ""
    ]
  , formField "catalog::Catalog number" [ inputText "catalog" model.catalog Catalog GRE.valCatalog ]
  , formField "website::Website" [ inputText "website" model.website Website (style "width" "500px" :: GRE.valWebsite) ]
  , tr [ class "newpart" ] [ td [ colspan 2 ] [] ]
  , formField "External Links" [ Html.map ExtLinks (EL.view model.extlinks) ]

  , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Database relations" ] ]
  , formField "Visual novels"
    [ if List.isEmpty model.vn then b [ class "standout" ] [ text "No visual novels selected.", br [] [] ]
      else table [] <| List.indexedMap (\i v -> tr []
        [ td [ style "text-align" "right" ] [ b [ class "grayedout" ] [ text <| v.vid ++ ":" ] ]
        , td [] [ a [ href <| "/" ++ v.vid ] [ text v.title ] ]
        , td [] [ inputSelect "" v.rtype (VNRType i) [style "width" "100px"] GT.releaseTypes ]
        , td [] [ inputButton "remove" (VNDel i) [] ]
        ]
      ) model.vn
    , A.view vnConfig model.vnAdd [placeholder "Add visual novel..."]
    ]
  , tr [ class "newpart" ] [ td [ colspan 2 ] [] ]
  , formField "Producers"
    [ table [ class "compact" ] <| List.indexedMap (\i p -> tr []
        [ td [ style "text-align" "right" ] [ b [ class "grayedout" ] [ text <| p.pid ++ ":" ] ]
        , td [] [ a [ href <| "/" ++ p.pid ] [ text p.name ] ]
        , td [] [ inputSelect "" (p.developer, p.publisher) (ProdRole i) [style "width" "100px"] [((True,False), "Developer"), ((False,True), "Publisher"), ((True,True), "Both")] ]
        , td [] [ inputButton "remove" (ProdDel i) [] ]
        ]
      ) model.prod
    , A.view producerConfig model.prodAdd [placeholder "Add producer..."]
    ]

  , tr [ class "newpart" ] [ td [ colspan 2 ] [] ]
  , formField "notes::Notes"
    [ TP.view "notes" model.notes Notes 700 [] [ b [ class "standout" ] [ text " (English please!) " ] ]
    , text "Miscellaneous notes/comments, information that does not fit in the above fields. E.g.: Types of censoring or for which releases this patch applies."
    ]
  ]

view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
  [ div [ class "mainbox" ]
    [ h1 [] [ text "General info" ]
    , viewGen model
    ]
  , div [ class "mainbox" ]
    [ fieldset [ class "submit" ]
      [ Html.map Editsum (Editsum.view model.editsum)
      , submitButton "Submit" model.state (isValid model)
      ]
    ]
  ]
