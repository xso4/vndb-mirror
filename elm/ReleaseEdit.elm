module ReleaseEdit exposing (main)

import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Set
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
  , subscriptions = sub
  }


type alias Model =
  { state      : Api.State
  , title      : String
  , original   : String
  , rtype      : String
  , official   : Bool
  , patch      : Bool
  , freeware   : Bool
  , doujin     : Bool
  , lang       : Set.Set String
  , langDd     : DD.Config Msg
  , plat       : Set.Set String
  , platDd     : DD.Config Msg
  , media      : List GRE.RecvMedia
  , gtin       : String
  , gtinValid  : Bool
  , catalog    : String
  , released   : D.RDate
  , minage     : Int
  , uncensored : Bool
  , resoX      : Int
  , resoY      : Int
  , resoConf   : A.Config Msg GRE.RecvResolutions
  , reso       : A.Model GRE.RecvResolutions
  , voiced     : Int
  , ani_story  : Int
  , ani_ero    : Int
  , website    : String
  , engineConf : A.Config Msg GRE.RecvEngines
  , engine     : A.Model GRE.RecvEngines
  , extlinks   : EL.Model GRE.RecvExtlinks
  , vn         : List GRE.RecvVn
  , vnAdd      : A.Model GApi.ApiVNResult
  , prod       : List GRE.RecvProducers
  , prodAdd    : A.Model GApi.ApiProducerResult
  , notes      : TP.Model
  , editsum    : Editsum.Model
  , id         : Maybe Int
  }


engineConf : List GRE.RecvEngines -> A.Config Msg GRE.RecvEngines
engineConf lst =
  { wrap   = Engine
  , id = "engine"
  , source =
    { source = A.Func (\s -> List.filter (\e -> String.contains (String.toLower s) (String.toLower e.engine)) lst |> List.take 10)
    , view   = \i -> [ text i.engine, b [ class "grayedout" ] [ text <| " (" ++ String.fromInt i.count ++ ")" ] ]
    , key    = \i -> i.engine
    }
  }


resoConf : List GRE.RecvResolutions -> A.Config Msg GRE.RecvResolutions
resoConf lst =
  { wrap   = Resolution
  , id = "resolution"
  , source =
    { source = A.Func (\s -> List.filter (\e -> String.contains (String.toLower s) (String.toLower e.resolution)) lst |> List.take 10)
    , view   = \i -> [ text i.resolution, b [ class "grayedout" ] [ text <| " (" ++ String.fromInt i.count ++ ")" ] ]
    , key    = \i -> i.resolution
    }
  }

resoFmt : Int -> Int -> String
resoFmt x y =
  case (x,y) of
    (0,0) -> ""
    (0,1) -> "Non-standard"
    _ -> String.fromInt x ++ "x" ++ String.fromInt y

resoParse : String -> Maybe (Int, Int)
resoParse s =
  let t =  String.replace "*" "x" s
        |> String.replace "×" "x"
        |> String.replace " " ""
        |> String.replace "\t" ""
        |> String.toLower |> String.trim
  in
  case (t, String.split "x" t) of
    ("", _) -> Just (0,0)
    ("non-standard", _) -> Just (0,1)
    (_, [sx,sy]) ->
      case (String.toInt sx, String.toInt sy) of
        (Just ix, Just iy) -> if ix < 1 || ix > 32767 || iy < 1 || iy > 32767 then Nothing else Just (ix,iy)
        _ -> Nothing
    _ -> Nothing


init : GRE.Recv -> Model
init d =
  { state      = Api.Normal
  , title      = d.title
  , original   = d.original
  , rtype      = d.rtype
  , official   = d.official
  , patch      = d.patch
  , freeware   = d.freeware
  , doujin     = d.doujin
  , lang       = Set.fromList <| List.map (\e -> e.lang) d.lang
  , langDd     = DD.init "lang" LangOpen
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
  , resoConf   = resoConf d.resolutions
  , reso       = A.init (resoFmt d.reso_x d.reso_y)
  , voiced     = d.voiced
  , ani_story  = d.ani_story
  , ani_ero    = d.ani_ero
  , website    = d.website
  , engineConf = engineConf d.engines
  , engine     = A.init d.engine
  , extlinks   = EL.new d.extlinks GEL.releaseSites
  , vn         = d.vn
  , vnAdd      = A.init ""
  , prod       = d.producers
  , prodAdd    = A.init ""
  , notes      = TP.bbcode d.notes
  , editsum    = { authmod = d.authmod, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden }
  , id         = d.id
  }


encode : Model -> GRE.Send
encode model =
  { id          = model.id
  , editsum     = model.editsum.editsum.data
  , hidden      = model.editsum.hidden
  , locked      = model.editsum.locked
  , title       = model.title
  , original    = model.original
  , rtype       = model.rtype
  , official    = model.official
  , patch       = model.patch
  , freeware    = model.freeware
  , doujin      = model.doujin
  , lang        = List.map (\l -> {lang=l    }) <| Set.toList model.lang
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
  , website     = model.website
  , engine      = model.engine.value
  , extlinks    = model.extlinks.links
  , vn          = List.map (\l -> {vid=l.vid}) model.vn
  , producers   = List.map (\l -> {pid=l.pid, developer=l.developer, publisher=l.publisher}) model.prod
  , notes       = model.notes.data
  }

vnConfig : A.Config Msg GApi.ApiVNResult
vnConfig = { wrap = VNSearch, id = "vnadd", source = A.vnSource }

producerConfig : A.Config Msg GApi.ApiProducerResult
producerConfig = { wrap = ProdSearch, id = "prodadd", source = A.producerSource }

sub : Model -> Sub Msg
sub m = Sub.batch [ DD.sub m.langDd, DD.sub m.platDd ]

type Msg
  = Title String
  | Original String
  | RType String
  | Official Bool
  | Patch Bool
  | Freeware Bool
  | Doujin Bool
  | Lang String Bool
  | LangOpen Bool
  | Plat String Bool
  | PlatOpen Bool
  | MediaType Int String
  | MediaQty Int Int
  | MediaDel Int
  | Gtin String
  | Catalog String
  | Released D.RDate
  | Minage Int
  | Uncensored Bool
  | Resolution (A.Msg GRE.RecvResolutions)
  | Voiced Int
  | AniStory Int
  | AniEro Int
  | Website String
  | Engine (A.Msg GRE.RecvEngines)
  | ExtLinks (EL.Msg GRE.RecvExtlinks)
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
    Title s    -> ({ model | title    = s }, Cmd.none)
    Original s -> ({ model | original = s }, Cmd.none)
    RType s    -> ({ model | rtype    = s }, Cmd.none)
    Official b -> ({ model | official = b }, Cmd.none)
    Patch b    -> ({ model | patch    = b }, Cmd.none)
    Freeware b -> ({ model | freeware = b }, Cmd.none)
    Doujin b   -> ({ model | doujin   = b }, Cmd.none)
    Lang s b   -> ({ model | lang     = if b then Set.insert s model.lang else Set.remove s model.lang }, Cmd.none)
    LangOpen b -> ({ model | langDd   = DD.toggle model.langDd b }, Cmd.none)
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
      let (nm, c, en) = A.update model.resoConf m model.reso
          nmod = { model | reso = Maybe.withDefault nm <| Maybe.map (\e -> A.clear nm e.resolution) en }
          n2mod = case resoParse nmod.reso.value of
            Just (x,y) -> { nmod | resoX = x, resoY = y }
            Nothing -> nmod
      in (n2mod, c)
    Voiced i   -> ({ model | voiced = i }, Cmd.none)
    AniStory i -> ({ model | ani_story = i }, Cmd.none)
    AniEro i   -> ({ model | ani_ero = i }, Cmd.none)
    Website s  -> ({ model | website = s }, Cmd.none)
    Engine m   ->
      let (nm, c, en) = A.update model.engineConf m model.engine
          nmod = case en of
            Just e  -> A.clear nm e.engine
            Nothing -> nm
      in ({ model | engine = nmod }, c)
    ExtLinks m -> ({ model | extlinks = EL.update m model.extlinks }, Cmd.none)

    VNDel i    -> ({ model | vn = delidx i model.vn }, Cmd.none)
    VNSearch m ->
      let (nm, c, res) = A.update vnConfig m model.vnAdd
      in case res of
        Nothing -> ({ model | vnAdd = nm }, c)
        Just v  ->
          if List.any (\vn -> vn.vid == v.id) model.vn
          then ({ model | vnAdd = nm }, c)
          else ({ model | vnAdd = A.clear nm "", vn = model.vn ++ [{ vid = v.id, title = v.title}] }, c)

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
  (  model.title == model.original
  || Set.isEmpty model.lang
  || hasDuplicates (List.map (\m -> (m.medium, m.qty)) model.media)
  || not model.gtinValid
  || List.isEmpty model.vn
  || resoParse model.reso.value == Nothing
  )


viewGen : Model -> Html Msg
viewGen model =
  table [ class "formtable" ]
  [ formField "title::Title (romaji)"
    [ inputText "title" model.title Title (style "width" "500px" :: GRE.valTitle)
    , if containsNonLatin model.title
      then b [ class "standout" ] [ br [] [], text "This title field should only contain latin-alphabet characters, please put the \"actual\" title in the field below and the romanization above." ]
      else text ""
    ]
  , formField "original::Original title"
    [ inputText "original" model.original Original (style "width" "500px" :: GRE.valOriginal)
    , if model.title /= "" && model.title == model.original
      then b [ class "standout" ] [ br [] [], text "Should not be the same as the Title (romaji). Leave blank is the original title is already in the latin alphabet" ]
      else if model.original /= "" && not (containsNonLatin model.original)
      then b [ class "standout" ] [ br [] [], text "Original title does not seem to contain any non-latin characters. Leave this field empty if the title is already in the latin alphabet" ]
      else if containsJapanese model.original && not (Set.isEmpty model.lang) && not (Set.member "ja" model.lang)
      then b [ class "standout" ] [ br [] [], text "Non-Japanese releases should (probably) not have a Japanese original title." ]
      else text ""
    ]

  , tr [ class "newpart" ] [ td [] [] ]
  , formField "rtype::Type" [ inputSelect "rtype" model.rtype RType [] GT.releaseTypes ]
  , formField "minage::Age rating" [ inputSelect "minage" model.minage Minage [] GT.ageRatings, text " (*)" ]
  , formField "" [ label [] [ inputCheck "" model.official Official, text " Official (i.e. sanctioned by the original developer, not fan-made)" ] ]
  , formField "" [ label [] [ inputCheck "" model.patch    Patch   , text " This release is a patch to another release.", text " (*)" ] ]
  , formField "" [ label [] [ inputCheck "" model.freeware Freeware, text " Freeware (i.e. available at no cost)" ] ]
  , if model.patch then text "" else
    formField "" [ label [] [ inputCheck "" model.doujin   Doujin  , text " Doujin (self-published, not by a company)" ] ]
  , formField "Release date" [ D.view model.released False False Released, text " Leave month or day blank if they are unknown." ]

  , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Format" ] ]
  , formField "Language(s)"
    [ div [ class "elm_dd_input", style "width" "500px" ] [ DD.view model.langDd Api.Normal
      (if Set.isEmpty model.lang
       then b [ class "standout" ] [ text "No language selected" ]
       else span [] <| List.intersperse (text ", ") <| List.map (\(l,t) -> span [ style "white-space" "nowrap" ] [ langIcon l, text t ]) <| List.filter (\(l,_) -> Set.member l model.lang) GT.languages)
      <| \() -> [ ul [ style "columns" "2"] <| List.map (\(l,t) -> li [] [ linkRadio (Set.member l model.lang) (Lang l) [ langIcon l, text t ] ]) GT.languages ]
    ] ]
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
            , td [] [ if q then inputSelect "" m.qty (MediaQty i) [ style "width" "100px" ] <| List.map (\a -> (a,String.fromInt a)) <| List.range 1 20 else text "" ]
            , td [] [ if m.medium == "unk" then text "" else inputButton "remove" (MediaDel i) [] ]
            ]
      ) <| model.media ++ [{medium = "unk", qty = 0}]
    , if hasDuplicates (List.map (\m -> (m.medium, m.qty)) model.media)
      then b [ class "standout" ] [ text "List contains duplicates", br [] [] ]
      else text ""
    ]

  , if model.patch then text "" else
    formField "engine::Engine" [ A.view model.engineConf model.engine [] ]
  , if model.patch then text "" else
    formField "resolution::Resolution"
    [ A.view model.resoConf model.reso []
    , if resoParse model.reso.value == Nothing then b [ class "standout" ] [ text " Invalid resolution" ] else text ""
    ]
  , if model.patch then text "" else
    formField "voiced::Voiced" [ inputSelect "voiced" model.voiced Voiced [] GT.voiced ]
  , if model.patch then text "" else
    formField "ani_story::Animations"
    [ inputSelect "ani_story" model.ani_story AniStory [] GT.animated
    , if model.minage == 18 then text " <= story | ero scenes => " else text ""
    , if model.minage == 18 then inputSelect "" model.ani_ero AniEro [] GT.animated else text ""
    ]
  , if model.minage /= 18 then text "" else
    formField "" [ label [] [ inputCheck "" model.uncensored Uncensored, text " Uncensored (No mosaic or other optical censoring, only check if this release has erotic content)" ] ]

  , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "External identifiers & links" ] ]
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
        [ td [ style "text-align" "right" ] [ b [ class "grayedout" ] [ text <| "v" ++ String.fromInt v.vid ++ ":" ] ]
        , td [] [ a [ href <| "/v" ++ String.fromInt v.vid ] [ text v.title ] ]
        , td [] [ inputButton "remove" (VNDel i) [] ]
        ]
      ) model.vn
    , A.view vnConfig model.vnAdd [placeholder "Add visual novel..."]
    ]
  , tr [ class "newpart" ] [ td [ colspan 2 ] [] ]
  , formField "Producers"
    [ table [ class "compact" ] <| List.indexedMap (\i p -> tr []
        [ td [ style "text-align" "right" ] [ b [ class "grayedout" ] [ text <| "p" ++ String.fromInt p.pid ++ ":" ] ]
        , td [] [ a [ href <| "/p" ++ String.fromInt p.pid ] [ text p.name ] ]
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
