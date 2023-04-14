port module VNEdit exposing (main)

import Html exposing (..)
import Html.Events exposing (..)
import Html.Keyed as K
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Browser.Dom as Dom
import Dict
import Set
import Task
import Date
import Process
import File exposing (File)
import File.Select as FSel
import Lib.Ffi as Ffi
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Autocomplete as A
import Lib.RDate as RDate
import Lib.Api as Api
import Lib.Editsum as Editsum
import Lib.Image as Img
import Gen.VN as GV
import Gen.VNEdit as GVE
import Gen.Types as GT
import Gen.Api as GApi


main : Program GVE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Date.today |> Task.perform Today)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


port ivRefresh : Bool -> Cmd msg

type Tab
  = General
  | Image
  | Staff
  | Cast
  | Screenshots
  | All

type alias Model =
  { state       : Api.State
  , tab         : Tab
  , today       : Int
  , invalidDis  : Bool
  , editsum     : Editsum.Model
  , titles      : List GVE.RecvTitles
  , alias       : String
  , desc        : TP.Model
  , devStatus   : Int
  , olang       : String
  , length      : Int
  , lWikidata   : Maybe Int
  , lRenai      : String
  , vns         : List GVE.RecvRelations
  , vnSearch    : A.Model GApi.ApiVNResult
  , anime       : List GVE.RecvAnime
  , animeSearch : A.Model GApi.ApiAnimeResult
  , image       : Img.Image
  , editions    : List GVE.RecvEditions
  , staff       : List GVE.RecvStaff
    -- Search boxes matching the list of editions (n+1), first entry is for the NULL edition.
  , staffSearch : List (A.Config Msg GApi.ApiStaffResult, A.Model GApi.ApiStaffResult)
  , seiyuu      : List GVE.RecvSeiyuu
  , seiyuuSearch: A.Model GApi.ApiStaffResult
  , seiyuuDef   : String -- character id for newly added seiyuu
  , screenshots : List (Int,Img.Image,Maybe String) -- internal id, img, rel
  , scrQueue    : List File
  , scrUplRel   : Maybe String
  , scrUplNum   : Maybe Int
  , scrId       : Int -- latest used internal id
  , releases    : List GVE.RecvReleases
  , reltitles   : List { id: String, title: String }
  , chars       : List GVE.RecvChars
  , id          : Maybe String
  , dupCheck    : Bool
  , dupVNs      : List GApi.ApiVNResult
  }


init : GVE.Recv -> Model
init d =
  { state       = Api.Normal
  , tab         = General
  , today       = 0
  , invalidDis  = False
  , editsum     = { authmod = d.authmod, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden, hasawait = False }
  , titles      = d.titles
  , alias       = d.alias
  , desc        = TP.bbcode d.desc
  , devStatus   = d.devstatus
  , olang       = d.olang
  , length      = d.length
  , lWikidata   = d.l_wikidata
  , lRenai      = d.l_renai
  , vns         = d.relations
  , vnSearch    = A.init ""
  , anime       = d.anime
  , animeSearch = A.init ""
  , image       = Img.info d.image_info
  , editions    = d.editions
  , staff       = d.staff
  , staffSearch = (staffConfig Nothing, A.init "") :: List.map (\e -> (staffConfig (Just e.eid), A.init "")) d.editions
  , seiyuu      = d.seiyuu
  , seiyuuSearch= A.init ""
  , seiyuuDef   = Maybe.withDefault "" <| List.head <| List.map (\c -> c.id) d.chars
  , screenshots = List.indexedMap (\n i -> (n, Img.info (Just i.info), i.rid)) d.screenshots
  , scrQueue    = []
  , scrUplRel   = Nothing
  , scrUplNum   = Nothing
  , scrId       = 100
  , releases    = d.releases
  , reltitles   = d.reltitles
  , chars       = d.chars
  , id          = d.id
  , dupCheck    = False
  , dupVNs      = []
  }


encode : Model -> GVE.Send
encode model =
  { id          = model.id
  , editsum     = model.editsum.editsum.data
  , hidden      = model.editsum.hidden
  , locked      = model.editsum.locked
  , titles      = model.titles
  , alias       = model.alias
  , devstatus   = model.devStatus
  , desc        = model.desc.data
  , olang       = model.olang
  , length      = model.length
  , l_wikidata  = model.lWikidata
  , l_renai     = model.lRenai
  , relations   = List.map (\v -> { vid = v.vid, relation = v.relation, official = v.official }) model.vns
  , anime       = List.map (\a -> { aid = a.aid }) model.anime
  , image       = model.image.id
  , editions    = model.editions
  , staff       = List.map (\s -> { aid = s.aid, eid = s.eid, note = s.note, role = s.role }) model.staff
  , seiyuu      = List.map (\s -> { aid = s.aid, cid = s.cid, note = s.note }) model.seiyuu
  , screenshots = List.map (\(_,i,r) -> { scr = Maybe.withDefault "" i.id, rid = r }) model.screenshots
  }

vnConfig : A.Config Msg GApi.ApiVNResult
vnConfig = { wrap = VNSearch, id = "relationadd", source = A.vnSource }

animeConfig : A.Config Msg GApi.ApiAnimeResult
animeConfig = { wrap = AnimeSearch, id = "animeadd", source = A.animeSource False }

staffConfig : Maybe Int -> A.Config Msg GApi.ApiStaffResult
staffConfig eid =
  { wrap = (StaffSearch eid)
  , id = "staffadd-" ++ Maybe.withDefault "" (Maybe.map String.fromInt eid)
  , source = A.staffSource
  }

seiyuuConfig : A.Config Msg GApi.ApiStaffResult
seiyuuConfig = { wrap = SeiyuuSearch, id = "seiyuuadd", source = A.staffSource }

type Msg
  = Noop
  | Today Date.Date
  | Editsum Editsum.Msg
  | Tab Tab
  | Invalid Tab
  | InvalidEnable
  | Submit
  | Submitted GApi.Response
  | Alias String
  | Desc TP.Msg
  | DevStatus Int
  | Length Int
  | LWikidata (Maybe Int)
  | LRenai String
  | TitleAdd String
  | TitleDel Int
  | TitleLang Int String
  | TitleTitle Int String
  | TitleLatin Int String
  | TitleOfficial Int Bool
  | TitleMain Int String
  | VNDel Int
  | VNRel Int String
  | VNOfficial Int Bool
  | VNSearch (A.Msg GApi.ApiVNResult)
  | AnimeDel Int
  | AnimeSearch (A.Msg GApi.ApiAnimeResult)
  | ImageSet String Bool
  | ImageSelect
  | ImageSelected File
  | ImageMsg Img.Msg
  | EditionAdd
  | EditionLang Int (Maybe String)
  | EditionName Int String
  | EditionOfficial Int Bool
  | EditionDel Int Int
  | StaffDel Int
  | StaffRole Int String
  | StaffNote Int String
  | StaffSearch (Maybe Int) (A.Msg GApi.ApiStaffResult)
  | SeiyuuDef String
  | SeiyuuDel Int
  | SeiyuuChar Int String
  | SeiyuuNote Int String
  | SeiyuuSearch (A.Msg GApi.ApiStaffResult)
  | ScrUplRel (Maybe String)
  | ScrUplSel
  | ScrUpl File (List File)
  | ScrMsg Int Img.Msg
  | ScrRel Int (Maybe String)
  | ScrDel Int
  | DupSubmit
  | DupResults GApi.Response


scrProcessQueue : (Model, Cmd Msg) -> (Model, Cmd Msg)
scrProcessQueue (model, msg) =
  case model.scrQueue of
    (f::fl) ->
      if List.any (\(_,i,_) -> i.imgState == Img.Loading) model.screenshots
      then (model, msg)
      else
        let (im,ic) = Img.upload Api.Sf f
        in ( { model | scrQueue = fl, scrId = model.scrId + 1, screenshots = model.screenshots ++ [(model.scrId, im, model.scrUplRel)] }
           , Cmd.batch [ msg, Cmd.map (ScrMsg model.scrId) ic ] )
    _ -> (model, msg)


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Noop       -> (model, Cmd.none)
    Today d    -> ({ model | today = RDate.fromDate d |> RDate.compact }, Cmd.none)
    Editsum m  -> let (nm,nc) = Editsum.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)
    Tab t      -> ({ model | tab = t }, Cmd.none)
    Invalid t  -> if model.invalidDis || model.tab == All || model.tab == t then (model, Cmd.none) else
                  ({ model | tab = t, invalidDis = True }, Task.attempt (always InvalidEnable) (Ffi.elemCall "reportValidity" "mainform" |> Task.andThen (\_ -> Process.sleep 100)))
    InvalidEnable -> ({ model | invalidDis = False }, Cmd.none)
    Alias s    -> ({ model | alias    = s, dupVNs = [] }, Cmd.none)
    Desc m     -> let (nm,nc) = TP.update m model.desc in ({ model | desc = nm }, Cmd.map Desc nc)
    DevStatus b-> ({ model | devStatus = b }, Cmd.none)
    Length n   -> ({ model | length = n }, Cmd.none)
    LWikidata n-> ({ model | lWikidata = n }, Cmd.none)
    LRenai s   -> ({ model | lRenai = s }, Cmd.none)

    TitleAdd s ->
      ({ model | titles = model.titles ++ [{ lang = s, title = "", latin = Nothing, official = True }], olang = if List.isEmpty model.titles then s else model.olang }
      , Task.attempt (always Noop) (Dom.focus ("title_" ++ s)))
    TitleDel i        -> ({ model | titles = delidx i model.titles }, Cmd.none)
    TitleLang i s     -> ({ model | titles = modidx i (\e -> { e | lang = s }) model.titles }, Cmd.none)
    TitleTitle i s    -> ({ model | titles = modidx i (\e -> { e | title = s }) model.titles }, Cmd.none)
    TitleLatin i s    -> ({ model | titles = modidx i (\e -> { e | latin = if s == "" then Nothing else Just s }) model.titles }, Cmd.none)
    TitleOfficial i s -> ({ model | titles = modidx i (\e -> { e | official = s }) model.titles }, Cmd.none)
    TitleMain i s     -> ({ model | olang = s, titles = modidx i (\e -> { e | official = True }) model.titles }, Cmd.none)

    VNDel idx        -> ({ model | vns = delidx idx model.vns }, Cmd.none)
    VNRel idx rel    -> ({ model | vns = modidx idx (\v -> { v | relation = rel }) model.vns }, Cmd.none)
    VNOfficial idx o -> ({ model | vns = modidx idx (\v -> { v | official = o   }) model.vns }, Cmd.none)
    VNSearch m ->
      let (nm, c, res) = A.update vnConfig m model.vnSearch
      in case res of
        Nothing -> ({ model | vnSearch = nm }, c)
        Just v ->
          if List.any (\l -> l.vid == v.id) model.vns
          then ({ model | vnSearch = A.clear nm "" }, c)
          else ({ model | vnSearch = A.clear nm "", vns = model.vns ++ [{ vid = v.id, title = v.title, relation = "seq", official = True }] }, c)

    AnimeDel i -> ({ model | anime = delidx i model.anime }, Cmd.none)
    AnimeSearch m ->
      let (nm, c, res) = A.update animeConfig m model.animeSearch
      in case res of
        Nothing -> ({ model | animeSearch = nm }, c)
        Just a ->
          if List.any (\l -> l.aid == a.id) model.anime
          then ({ model | animeSearch = A.clear nm "" }, c)
          else ({ model | animeSearch = A.clear nm "", anime = model.anime ++ [{ aid = a.id, title = a.title, original = a.original }] }, c)

    ImageSet s b -> let (nm, nc) = Img.new b s in ({ model | image = nm }, Cmd.map ImageMsg nc)
    ImageSelect -> (model, FSel.file ["image/png", "image/jpeg", "image/webp"] ImageSelected)
    ImageSelected f -> let (nm, nc) = Img.upload Api.Cv f in ({ model | image = nm }, Cmd.map ImageMsg nc)
    ImageMsg m -> let (nm, nc) = Img.update m model.image in ({ model | image = nm }, Cmd.map ImageMsg nc)

    EditionAdd ->
      let f n acc =
            case acc of
              Just x -> Just x
              Nothing -> if not (List.isEmpty (List.filter (\i -> i.eid == n) model.editions)) then Nothing else Just n
          newid = List.range 0 500 |> List.foldl f Nothing |> Maybe.withDefault 0
      in ({ model
          | editions = model.editions ++ [{ eid = newid, lang = Nothing, name = "", official = True }]
          , staffSearch = model.staffSearch ++ [(staffConfig (Just newid), A.init "")]
          }, Cmd.none)
    EditionDel idx eid ->
      ({ model
      | editions = delidx idx model.editions
      , staffSearch = delidx (idx + 1) model.staffSearch
      , staff = List.filter (\s -> s.eid /= Just eid) model.staff
      }, Cmd.none)
    EditionLang idx v -> ({ model | editions = modidx idx (\s -> { s | lang = v }) model.editions }, Cmd.none)
    EditionName idx v -> ({ model | editions = modidx idx (\s -> { s | name = v }) model.editions }, Cmd.none)
    EditionOfficial idx v -> ({ model | editions = modidx idx (\s -> { s | official = v }) model.editions }, Cmd.none)

    StaffDel idx    -> ({ model | staff = delidx idx model.staff }, Cmd.none)
    StaffRole idx v -> ({ model | staff = modidx idx (\s -> { s | role = v }) model.staff }, Cmd.none)
    StaffNote idx v -> ({ model | staff = modidx idx (\s -> { s | note = v }) model.staff }, Cmd.none)
    StaffSearch eid m ->
      let idx = List.indexedMap Tuple.pair model.editions
                |> List.filterMap (\(n,e) -> if Just e.eid == eid then Just (n+1) else Nothing)
                |> List.head |> Maybe.withDefault 0
      in case List.drop idx model.staffSearch |> List.head of
        Nothing -> (model, Cmd.none)
        Just (sconfig, smodel) ->
          let (nm, c, res) = A.update sconfig m smodel
              nnm = if res == Nothing then nm else A.clear nm ""
              nsearch = modidx idx (\(oc,om) -> (oc,nnm)) model.staffSearch
              nstaff s = [{ id = s.id, aid = s.aid, eid = eid, title = s.title, alttitle = s.alttitle, role = "staff", note = "" }]
          in case res of
            Nothing -> ({ model | staffSearch = nsearch }, c)
            Just s -> ({ model | staffSearch = nsearch, staff = model.staff ++ nstaff s }, c)

    SeiyuuDef c      -> ({ model | seiyuuDef = c }, Cmd.none)
    SeiyuuDel idx    -> ({ model | seiyuu = delidx idx model.seiyuu }, Cmd.none)
    SeiyuuChar idx v -> ({ model | seiyuu = modidx idx (\s -> { s | cid  = v }) model.seiyuu }, Cmd.none)
    SeiyuuNote idx v -> ({ model | seiyuu = modidx idx (\s -> { s | note = v }) model.seiyuu }, Cmd.none)
    SeiyuuSearch m ->
      let (nm, c, res) = A.update seiyuuConfig m model.seiyuuSearch
      in case res of
        Nothing -> ({ model | seiyuuSearch = nm }, c)
        Just s -> ({ model | seiyuuSearch = A.clear nm "", seiyuu = model.seiyuu ++ [{ id = s.id, aid = s.aid, title = s.title, alttitle = s.alttitle, cid = model.seiyuuDef, note = "" }] }, c)

    ScrUplRel s -> ({ model | scrUplRel = s }, Cmd.none)
    ScrUplSel -> (model, FSel.files ["image/png", "image/jpeg", "image/webp"] ScrUpl)
    ScrUpl f1 fl ->
      if 1 + List.length fl > 10 - List.length model.screenshots
      then ({ model | scrUplNum = Just (1 + List.length fl) }, Cmd.none)
      else scrProcessQueue ({ model | scrQueue = (f1::fl), scrUplNum = Nothing }, Cmd.none)
    ScrMsg id m ->
      let f (i,s,r) =
            if i /= id then ((i,s,r), Cmd.none)
            else let (nm,nc) = Img.update m s in ((i,nm,r), Cmd.map (ScrMsg id) nc)
          lst = List.map f model.screenshots
      in scrProcessQueue ({ model | screenshots = List.map Tuple.first lst }, Cmd.batch (ivRefresh True :: List.map Tuple.second lst))
    ScrRel n s -> ({ model | screenshots = List.map (\(i,img,r) -> if i == n then (i,img,s) else (i,img,r)) model.screenshots }, Cmd.none)
    ScrDel n   -> ({ model | screenshots = List.filter (\(i,_,_) -> i /= n) model.screenshots }, ivRefresh True)

    DupSubmit ->
      if List.isEmpty model.dupVNs
      then ({ model | state = Api.Loading }, GV.send { hidden = True, search = (List.concatMap (\e -> [e.title, Maybe.withDefault "" e.latin]) model.titles) ++ String.lines model.alias } DupResults)
      else ({ model | dupCheck = True, dupVNs = [] }, Cmd.none)
    DupResults (GApi.VNResult vns) ->
      if List.isEmpty vns
      then ({ model | state = Api.Normal, dupCheck = True, dupVNs = [] }, Cmd.none)
      else ({ model | state = Api.Normal, dupVNs = vns }, Cmd.none)
    DupResults r -> ({ model | state = Api.Error r }, Cmd.none)

    Submit -> ({ model | state = Api.Loading }, GVE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


-- TODO: Fuzzier matching? Exclude stuff like 'x Edition', etc.
relAlias : Model -> Maybe { id: String, title: String }
relAlias model =
  let a = String.toLower model.alias |> String.lines |> List.filter (\l -> l /= "") |> Set.fromList
  in List.filter (\r -> Set.member (String.toLower r.title) a) model.reltitles |> List.head


isValid : Model -> Bool
isValid model = not
  (  List.any (\e -> e.title /= "" && Just e.title == e.latin) model.titles
  || List.isEmpty model.titles
  || relAlias model /= Nothing
  || not (Img.isValid model.image)
  || List.any (\(_,i,r) -> r == Nothing || not (Img.isValid i)) model.screenshots
  || not (List.isEmpty model.scrQueue)
  || hasDuplicates (List.map (\e -> (Maybe.withDefault "" e.lang, e.name)) model.editions)
  || hasDuplicates (List.map (\s -> (s.aid, Maybe.withDefault -1 s.eid, s.role)) model.staff)
  || hasDuplicates (List.map (\s -> (s.aid, s.cid)) model.seiyuu)
  )


view : Model -> Html Msg
view model =
  let
    title i e = tr []
      [ td [] [ langIcon e.lang ]
      , td []
        [ inputText ("title_"++e.lang) e.title (TitleTitle i) (style "width" "500px" :: onInvalid (Invalid General) :: placeholder "Title (in the original script)" :: GVE.valTitlesTitle)
        , if not (e.latin /= Nothing || containsNonLatin e.title) then text "" else span []
          [ br [] []
          , inputText "" (Maybe.withDefault "" e.latin) (TitleLatin i) (style "width" "500px" :: onInvalid (Invalid General) :: placeholder "Romanization" :: GVE.valTitlesLatin)
          , case e.latin of
              Just s -> if containsNonLatin s then b [ class "standout" ] [ br [] [], text "Romanization should only consist of characters in the latin alphabet." ] else text ""
              Nothing -> text ""
          ]
        , if List.length model.titles == 1 then text "" else span []
          [ br [] []
          , label [] [ inputRadio "olang" (e.lang == model.olang) (\_ -> TitleMain i e.lang), text " main title (the language the VN was originally written in)" ]
          ]
        , if e.lang == model.olang then text "" else span []
          [ br [] []
          , label [] [ inputCheck "" e.official (TitleOfficial i), text " official title (from the developer or licensed localization; not from a fan translation)" ]
          , br [] []
          , inputButton "remove" (TitleDel i) []
          ]
        , br_ 2
        ]
      ]

    titles =
      let lines = List.filter (\e -> e /= "") <| String.lines <| String.toLower model.alias
      in
      [ formField "Title(s)"
        [ table [] <| List.indexedMap title model.titles
        , inputSelect "" "" TitleAdd [] <| ("", "- Add title -") :: List.filter (\(l,_) -> not (List.any (\e -> e.lang == l) model.titles)) scriptLangs
        , br_ 2
        ]
      , formField "alias::Aliases"
        [ inputTextArea "alias" model.alias Alias (rows 3 :: onInvalid (Invalid General) :: GVE.valAlias)
        , br [] []
        , if hasDuplicates lines
          then b [ class "standout" ] [ text "List contains duplicate aliases.", br [] [] ]
          else if contains lines <| List.map String.toLower <| List.concatMap (\e -> [e.title, Maybe.withDefault "" e.latin]) model.titles
          then b [ class "standout" ] [ text "Titles listed above should not also be added as alias.", br [] [] ]
          else
            case relAlias model of
              Nothing -> text ""
              Just r  -> span []
                [ b [ class "standout" ] [ text "Release titles should not be added as alias." ]
                , br [] []
                , text "Release: "
                , a [ href <| "/"++r.id ] [ text r.title ]
                , br [] [], br [] []
                ]
        , text "List of additional titles or abbreviations. One line for each alias. Can include both official (japanese/english) titles and unofficial titles used around net."
        , br [] []
        , text "Titles that are listed in the releases should not be added here!"
        ]
      ]

    geninfo = titles ++
      [ formField "desc::Description"
        [ TP.view "desc" model.desc Desc 600 (style "height" "180px" :: onInvalid (Invalid General) :: GVE.valDesc) [ b [ class "standout" ] [ text "English please!" ] ]
        , text "Short description of the main story. Please do not include spoilers, and don't forget to list the source in case you didn't write the description yourself."
        ]
      , formField "devstatus::Development status"
        [ inputSelect "devstatus" model.devStatus DevStatus [] GT.devStatus
        , if model.devStatus == 0
            && not (List.isEmpty model.releases)
            && List.isEmpty (List.filter (\r -> r.rtype == "complete" && r.released <= model.today) model.releases)
          then span []
               [ br [] []
               , b [ class "standout" ] [ text "Development is marked as finished, but there is no complete release in the database." ]
               , br [] []
               , text "Please adjust the development status or ensure there is a completed release."
               ]
          else text ""
        , if model.devStatus /= 0
            && not (List.isEmpty (List.filter (\r -> r.rtype == "complete" && r.released <= model.today) model.releases))
          then span []
               [ br [] []
               , b [ class "standout" ] [ text "Development is not marked as finished, but there is a complete release in the database." ]
               , br [] []
               , text "Please adjust the development status or set the release to partial or TBA."
               ]
          else text ""
        ]
      , formField "length::Length"
        [ inputSelect "length" model.length Length [] GT.vnLengths
        , text " (only displayed if there are no length votes)" ]
      , formField "l_wikidata::Wikidata ID" [ inputWikidata "l_wikidata" model.lWikidata LWikidata [onInvalid (Invalid General)] ]
      , formField "l_renai::Renai.us link" [ text "http://renai.us/game/", inputText "l_renai" model.lRenai LRenai (onInvalid (Invalid General) :: GVE.valL_Renai), text ".shtml" ]

      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Database relations" ] ]
      , formField "Related VNs"
        [ if List.isEmpty model.vns then text ""
          else table [] <| List.indexedMap (\i v -> tr []
            [ td [ style "text-align" "right" ] [ small [] [ text <| v.vid ++ ":" ] ]
            , td [ style "text-align" "right"] [ a [ href <| "/" ++ v.vid ] [ text v.title ] ]
            , td []
              [ text "is an "
              , label [] [ inputCheck "" v.official (VNOfficial i), text " official" ]
              , inputSelect "" v.relation (VNRel i) [] GT.vnRelations
              , text " of this VN"
              ]
            , td [] [ inputButton "remove" (VNDel i) [] ]
            ]
          ) model.vns
        , A.view vnConfig model.vnSearch [placeholder "Add visual novel..."]
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [] ]
      , formField "Related anime"
        [ if List.isEmpty model.anime then text ""
          else table [] <| List.indexedMap (\i e -> tr []
            [ td [ style "text-align" "right" ] [ small [] [ text <| "a" ++ String.fromInt e.aid ++ ":" ] ]
            , td [] [ a [ href <| "https://anidb.net/anime/" ++ String.fromInt e.aid ] [ text e.title ] ]
            , td [] [ inputButton "remove" (AnimeDel i) [] ]
            ]
          ) model.anime
        , A.view animeConfig model.animeSearch [placeholder "Add anime..."]
        ]
      ]

    image =
      table [ class "formimage" ] [ tr []
      [ td [] [ Img.viewImg model.image ]
      , td []
        [ h2 [] [ text "Image ID" ]
        , input ([ type_ "text", class "text", tabindex 10, value (Maybe.withDefault "" model.image.id), onInputValidation ImageSet, onInvalid (Invalid Image) ] ++ GVE.valImage) []
        , br [] []
        , text "Use an image that already exists on the server or empty to remove the current image."
        , br_ 2
        , h2 [] [ text "Upload new image" ]
        , inputButton "Browse image" ImageSelect []
        , br [] []
        , text "Preferably the cover of the CD/DVD/package. Image must be in JPEG, PNG or WebP format and at most 10 MiB. Images larger than 256x400 will automatically be resized."
        , case Img.viewVote model.image ImageMsg (Invalid Image) of
            Nothing -> text ""
            Just v ->
              div []
              [ br [] []
              , text "Please flag this image: (see the ", a [ href "/d19" ] [ text "image flagging guidelines" ], text " for guidance)"
              , v
              ]
        ]
      ] ]

    staff =
      let
        head lst =
          if List.isEmpty lst then text "" else
            thead [] [ tr []
            [ td [] []
            , td [] [ text "Staff" ]
            , td [] [ text "Role" ]
            , td [] [ text "Note" ]
            , td [] []
            ] ]
        foot searchn lst (sconfig, smodel) =
          tfoot [] [ tr [] [ td [] [], td [ colspan 4 ]
          [ text ""
          , if hasDuplicates (List.map (\(_,s) -> (s.aid, s.role)) lst)
            then b [ class "standout" ] [ text "List contains duplicate staff roles.", br [] [] ]
            else text ""
          , A.view sconfig smodel [placeholder "Add staff..."]
          , if searchn > 0 then text "" else span []
            [ text "Can't find the person you're looking for? You can "
            , a [ href "/s/new" ] [ text "create a new entry" ]
            , text ", but "
            , a [ href "/s/all" ] [ text "please check for aliasses first." ]
            , br [] []
            , text "If one person performed several roles, you can add multiple entries with different major roles."
            ]
          ] ] ]
        item (n,s) = tr []
          [ td [ style "text-align" "right" ] [ small [] [ text <| s.id ++ ":" ] ]
          , td [] [ a [ href <| "/" ++ s.id ] [ text s.title ] ]
          , td [] [ inputSelect "" s.role (StaffRole n) [style "width" "150px" ] GT.creditTypes ]
          , td [] [ inputText "" s.note (StaffNote n) (style "width" "300px" :: onInvalid (Invalid Staff) :: GVE.valStaffNote) ]
          , td [] [ inputButton "remove" (StaffDel n) [] ]
          ]
        edition searchn edi =
          let eid = Maybe.map (\e -> e.eid) edi
              lst = List.indexedMap Tuple.pair model.staff |> List.filter (\(_,s) -> s.eid == eid)
              sch = List.drop searchn model.staffSearch |> List.head
          in div [style "margin" "0 0 30px 0"]
             [ Maybe.withDefault (if List.isEmpty model.editions then text "" else h2 [] [ text "Original edition" ])
               <| Maybe.map (\e -> h2 [] [ text (if e.name == "" then "New edition" else e.name) ]) edi
             , case edi of
                 Nothing -> text ""
                 Just e ->
                   div [style "margin" "5px 0 0 15px"]
                   [ inputText "" e.name (EditionName (searchn-1)) (placeholder "Edition title" :: style "width" "300px" :: onInvalid (Invalid Staff) :: GVE.valEditionsName)
                   , inputSelect "" e.lang (EditionLang (searchn-1)) [style "width" "150px"]
                     ((Nothing, "Original language") :: List.map (\(i,l) -> (Just i, l)) scriptLangs)
                   , text " ", label [] [ inputCheck "" e.official (EditionOfficial (searchn-1)), text " official" ]
                   , inputButton "remove edition" (EditionDel (searchn-1) e.eid) [style "margin-left" "30px"]
                   ]
             , table [style "margin" "5px 0 0 15px"]
               <| head lst
               :: Maybe.withDefault (text "") (Maybe.map (foot searchn lst) sch)
               :: List.map item lst
             ]
      in edition 0 Nothing
         :: List.indexedMap (\n e -> edition (n+1) (Just e)) model.editions
         ++ [ br [] [], inputButton "Add edition" EditionAdd [] ]



    cast =
      let
        chars = List.map (\c -> (c.id, c.title ++ " (" ++ c.id ++ ")")) model.chars
        head =
          if List.isEmpty model.seiyuu then [] else [
            thead [] [ tr []
            [ td [] [ text "Character" ]
            , td [] [ text "Cast" ]
            , td [] [ text "Note" ]
            , td [] []
            ] ] ]
        foot =
          tfoot [] [ tr [] [ td [ colspan 4 ]
          [ br [] []
          , b [] [ text "Add cast" ]
          , br [] []
          , if hasDuplicates (List.map (\s -> (s.aid, s.cid)) model.seiyuu)
            then b [ class "standout" ] [ text "List contains duplicate cast roles.", br [] [] ]
            else text ""
          , inputSelect "" model.seiyuuDef SeiyuuDef [] chars
          , text " voiced by "
          , div [ style "display" "inline-block" ] [ A.view seiyuuConfig model.seiyuuSearch [] ]
          , br [] []
          , text "Can't find the person you're looking for? You can "
          , a [ href "/s/new" ] [ text "create a new entry" ]
          , text ", but "
          , a [ href "/s/all" ] [ text "please check for aliasses first." ]
          ] ] ]
        item n s = tr []
          [ td [] [ inputSelect "" s.cid (SeiyuuChar n) []
            <| chars ++ if List.any (\c -> c.id == s.cid) model.chars then [] else [(s.cid, "[deleted/moved character: " ++ s.cid ++ "]")] ]
          , td []
            [ small [] [ text <| s.id ++ ":" ]
            , a [ href <| "/" ++ s.id ] [ text s.title ] ]
          , td [] [ inputText "" s.note (SeiyuuNote n) (style "width" "300px" :: onInvalid (Invalid Cast) :: GVE.valSeiyuuNote) ]
          , td [] [ inputButton "remove" (SeiyuuDel n) [] ]
          ]
      in
        if model.id == Nothing
        then text <| "Voice actors can be added to this visual novel once it has character entries associated with it. "
                  ++ "To do so, first create this entry without cast, then create the appropriate character entries, and finally come back to this form by editing the visual novel."
        else if List.isEmpty model.chars && List.isEmpty model.seiyuu
        then p []
             [ text "This visual novel does not have any characters associated with it (yet). Please "
             , a [ href <| "/" ++ Maybe.withDefault "" model.id ++ "/addchar" ] [ text "add the appropriate character entries" ]
             , text " first and then come back to this form to assign voice actors."
             ]
        else table [] <| head ++ [ foot ] ++ List.indexedMap item model.seiyuu

    screenshots =
      let
        rellist = List.map (\r -> (Just r.id, RDate.showrel r)) model.releases
        scr n (id, i, rel) = (String.fromInt id, tr [] <|
          let getdim img = Maybe.map (\nfo -> (nfo.width, nfo.height)) img |> Maybe.withDefault (0,0)
              imgdim = getdim i.img
              relnfo = List.filter (\r -> Just r.id == rel) model.releases |> List.head
              reldim = relnfo |> Maybe.andThen (\r -> if r.reso_x == 0 then Nothing else Just (r.reso_x, r.reso_y))
              dimstr (x,y) = String.fromInt x ++ "x" ++ String.fromInt y
          in
          [ td [] [ Img.viewImg i ]
          , td [] [ Img.viewVote i (ScrMsg id) (Invalid Screenshots) |> Maybe.withDefault (text "") ]
          , td []
            [ b [] [ text <| "Screenshot #" ++ String.fromInt (n+1) ]
            , text " (", a [ href "#", onClickD (ScrDel id) ] [ text "remove" ], text ")"
            , br [] []
            , text <| "Image resolution: " ++ dimstr imgdim
            , br [] []
            , text <| Maybe.withDefault "" <| Maybe.map (\dim -> "Release resolution: " ++ dimstr dim) reldim
            , span [] <|
              if reldim == Just imgdim then [ text " ✔", br [] [] ]
              else if reldim /= Nothing
              then [ text " ❌"
                   , br [] []
                   , b [ class "standout" ] [ text "WARNING: Resolutions do not match, please take screenshots with the correct resolution and make sure to crop them correctly!" ]
                   ]
              else if i.img /= Nothing && rel /= Nothing && List.any (\(_,si,sr) -> sr == rel && si.img /= Nothing && imgdim /= getdim si.img) model.screenshots
              then [ b [ class "standout" ] [ text "WARNING: Inconsistent image resolutions for the same release, please take screenshots with the correct resolution and make sure to crop them correctly!" ]
                   , br [] []
                   ]
              else [ br [] [] ]
            , br [] []
            , inputSelect "" rel (ScrRel id) [style "width" "500px"] <| rellist ++
              case (relnfo, rel) of
                (_, Nothing) -> [(Nothing, "[No release selected]")]
                (Nothing, Just r) -> [(Just r, "[Deleted or unlinked release: " ++ r ++ "]")]
                _ -> []
            ]
          ])

        add =
          let free = 10 - List.length model.screenshots
          in
          if not (List.isEmpty model.scrQueue)
          then [ b [] [ text "Uploading screenshots" ]
               , br [] []
               , text <| (String.fromInt (List.length model.scrQueue)) ++ " remaining... "
               , span [ class "spinner" ] []
               ]
          else if free <= 0
          then [ b [] [ text "Enough screenshots" ]
               , br [] []
               , text "The limit of 10 screenshots per visual novel has been reached. If you want to add a new screenshot, please remove an existing one first."
               ]
          else
            [ b [] [ text "Add screenshots" ]
            , br [] []
            , text <| String.fromInt free ++ " more screenshot" ++ (if free == 1 then "" else "s") ++ " can be added."
            , br [] []
            , inputSelect "" model.scrUplRel ScrUplRel [style "width" "500px"] ((Nothing, "-- select release --") :: rellist)
            , br [] []
            , if model.scrUplRel == Nothing then text "" else span []
              [ inputButton "Select images" ScrUplSel []
              , case model.scrUplNum of
                  Just num -> text " Too many images selected."
                  Nothing -> text ""
              , br [] []
              ]
            , br [] []
            , b [] [ text "Important reminder" ]
            , ul []
              [ li [] [ text "Screenshots must be in the native resolution of the game" ]
              , li [] [ text "Screenshots must not include window borders and should not have copyright markings" ]
              , li [] [ text "Don't only upload event CGs" ]
              ]
            , text "Read the ", a [ href "/d2#6" ] [ text "full guidelines" ], text " for more information."
            ]
      in
        if model.id == Nothing
        then text <| "Screenshots can be uploaded to this visual novel once it has a release entry associated with it. "
                  ++ "To do so, first create this entry without screenshots, then create the appropriate release entries, and finally come back to this form by editing the visual novel."
        else if List.isEmpty model.screenshots && List.isEmpty model.releases
        then p []
             [ text "This visual novel does not have any releases associated with it (yet). Please "
             , a [ href <| "/" ++ Maybe.withDefault "" model.id ++ "/add" ] [ text "add the appropriate release entries" ]
             , text " first and then come back to this form to upload screenshots."
             ]
        else
          table [ class "vnedit_scr" ]
          [ tfoot [] [ tr [] [ td [] [], td [ colspan 2 ] add ] ]
          , K.node "tbody" [] <| List.indexedMap scr model.screenshots
          ]

    newform () =
      form_ "" DupSubmit (model.state == Api.Loading)
      [ div [ class "mainbox" ] [ h1 [] [ text "Add a new visual novel" ], table [ class "formtable" ] titles ]
      , div [ class "mainbox" ]
        [ if List.isEmpty model.dupVNs then text "" else
          div []
          [ h1 [] [ text "Possible duplicates" ]
          , text "The following is a list of visual novels that match the title(s) you gave. "
          , text "Please check this list to avoid creating a duplicate visual novel entry. "
          , text "Be especially wary of items that have been deleted! To see why an entry has been deleted, click on its title."
          , ul [] <| List.map (\v -> li []
              [ a [ href <| "/" ++ v.id ] [ text v.title ]
              , if v.hidden then b [ class "standout" ] [ text " (deleted)" ] else text ""
              ]
            ) model.dupVNs
          ]
        , fieldset [ class "submit" ] [ submitButton (if List.isEmpty model.dupVNs then "Continue" else "Continue anyway") model.state (isValid model) ]
        ]
      ]

    fullform () =
      form_ "mainform" Submit (model.state == Api.Loading)
      [ div [ class "maintabs left" ]
        [ ul []
          [ li [ classList [("tabselected", model.tab == General    )] ] [ a [ href "#", onClickD (Tab General    ) ] [ text "General info" ] ]
          , li [ classList [("tabselected", model.tab == Image      )] ] [ a [ href "#", onClickD (Tab Image      ) ] [ text "Image"        ] ]
          , li [ classList [("tabselected", model.tab == Staff      )] ] [ a [ href "#", onClickD (Tab Staff      ) ] [ text "Staff"        ] ]
          , li [ classList [("tabselected", model.tab == Cast       )] ] [ a [ href "#", onClickD (Tab Cast       ) ] [ text "Cast"         ] ]
          , li [ classList [("tabselected", model.tab == Screenshots)] ] [ a [ href "#", onClickD (Tab Screenshots) ] [ text "Screenshots"  ] ]
          , li [ classList [("tabselected", model.tab == All        )] ] [ a [ href "#", onClickD (Tab All        ) ] [ text "All items"    ] ]
          ]
        ]
      , div [ class "mainbox", classList [("hidden", model.tab /= General     && model.tab /= All)] ] [ h1 [] [ text "General info" ], table [ class "formtable" ] geninfo ]
      , div [ class "mainbox", classList [("hidden", model.tab /= Image       && model.tab /= All)] ] [ h1 [] [ text "Image" ], image ]
      , div [ class "mainbox", classList [("hidden", model.tab /= Staff       && model.tab /= All)] ] ( h1 [] [ text "Staff" ] :: staff )
      , div [ class "mainbox", classList [("hidden", model.tab /= Cast        && model.tab /= All)] ] [ h1 [] [ text "Cast" ], cast ]
      , div [ class "mainbox", classList [("hidden", model.tab /= Screenshots && model.tab /= All)] ] [ h1 [] [ text "Screenshots" ], screenshots ]
      , div [ class "mainbox" ] [ fieldset [ class "submit" ]
          [ Html.map Editsum (Editsum.view model.editsum)
          , submitButton "Submit" model.state (isValid model)
          ]
        ]
      ]
  in if model.id == Nothing && not model.dupCheck then newform () else fullform ()
