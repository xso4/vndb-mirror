port module User.Edit exposing (main)

import Bitwise exposing (..)
import Set
import Task
import Process
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as K
import Browser
import Browser.Navigation exposing (load)
import Lib.Ffi as Ffi
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Api as Api
import Lib.Autocomplete as A
import Gen.Api as GApi
import Gen.Types as GT
import Gen.UserEdit as GUE


main : Program GUE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

port skinChange : String -> Cmd msg

type Tab = Profile | Preferences

type alias PassData =
  { cpass       : Bool
  , pass1       : String
  , pass2       : String
  , opass       : String
  }

type alias Model =
  { state       : Api.State
  , tab         : Tab
  , invalidDis  : Bool
  , id          : String
  , username    : String
  , nusername   : Maybe String
  , opts        : GUE.RecvOpts
  , admin       : Maybe GUE.SendAdmin
  , prefs       : Maybe GUE.SendPrefs
  , pass        : Maybe PassData
  , passNeq     : Bool
  , mailConfirm : Bool
  , traitSearch : A.Model GApi.ApiTraitResult
  }


init : GUE.Recv -> Model
init d =
  { state       = Api.Normal
  , tab         = Profile
  , invalidDis  = False
  , id          = d.id
  , username    = d.username
  , nusername   = Nothing
  , opts        = d.opts
  , admin       = d.admin
  , prefs       = d.prefs
  , pass        = Maybe.map (always { cpass = False, pass1 = "", pass2 = "", opass = "" }) d.prefs
  , passNeq     = False
  , mailConfirm = False
  , traitSearch = A.init ""
  }


type AdminMsg
  = PermBoard Bool
  | PermReview Bool
  | PermBoardmod Bool
  | PermEdit Bool
  | PermImgvote Bool
  | PermLengthvote Bool
  | PermTag Bool
  | PermDbmod Bool
  | PermTagmod Bool
  | PermUsermod Bool
  | IgnVotes Bool
  | PermNone
  | PermDefault

type LangPrefMsg
  = LangAdd
  | LangDel Int
  | LangSet Int String
  | LangType Int (Bool,Bool)
  | LangLatin Int Bool

type PrefMsg
  = EMail String
  | MaxSexual Int
  | MaxViolence Int
  | TraitsSexual Bool
  | Spoilers Int
  | TagsAll Bool
  | TagsCont Bool
  | TagsEro Bool
  | TagsTech Bool
  | VNRelLangs (List String)
  | VNRelOLang Bool
  | VNRelMTL Bool
  | StaffEdLangs (List String)
  | StaffEdOLang Bool
  | StaffEdUnoff Bool
  | ProdRel Bool
  | Skin String
  | Css String
  | NoAds Bool
  | NoFancy Bool
  | Support Bool
  | PubSkin Bool
  | Uniname String
  | TitleLang LangPrefMsg
  | AltTitleLang LangPrefMsg
  | TraitDel Int

type PassMsg
  = CPass Bool
  | OPass String
  | Pass1 String
  | Pass2 String

type Msg
  = Tab Tab
  | Invalid Tab
  | InvalidEnable
  | Username (Maybe String)
  | Admin AdminMsg
  | Prefs PrefMsg
  | Pass PassMsg
  | TraitSearch (A.Msg GApi.ApiTraitResult)
  | Submit
  | Submitted GApi.Response


traitConfig : A.Config Msg GApi.ApiTraitResult
traitConfig = { wrap = TraitSearch, id = "traitadd", source = A.traitSource }


updateAdmin : AdminMsg -> GUE.SendAdmin -> GUE.SendAdmin
updateAdmin msg model =
  case msg of
    PermBoard b    -> { model | perm_board    = b }
    PermReview b   -> { model | perm_review   = b }
    PermBoardmod b -> { model | perm_boardmod = b }
    PermEdit b     -> { model | perm_edit     = b }
    PermImgvote b  -> { model | perm_imgvote  = b }
    PermLengthvote b->{ model | perm_lengthvote=b }
    PermTag b      -> { model | perm_tag      = b }
    PermDbmod b    -> { model | perm_dbmod    = b }
    PermTagmod b   -> { model | perm_tagmod   = b }
    PermUsermod b  -> { model | perm_usermod  = b }
    IgnVotes b     -> { model | ign_votes     = b }
    PermNone       ->
      { perm_board    = False
      , perm_review   = False
      , perm_boardmod = False
      , perm_edit     = False
      , perm_imgvote  = False
      , perm_lengthvote=False
      , perm_tag      = False
      , perm_dbmod    = False
      , perm_tagmod   = False
      , perm_usermod  = False
      , ign_votes     = model.ign_votes
      }
    PermDefault    ->
      { perm_board    = True
      , perm_review   = True
      , perm_boardmod = False
      , perm_edit     = True
      , perm_imgvote  = True
      , perm_lengthvote=True
      , perm_tag      = True
      , perm_dbmod    = False
      , perm_tagmod   = False
      , perm_usermod  = False
      , ign_votes     = model.ign_votes
      }

updateLangPrefs : LangPrefMsg -> List GUE.SendPrefsTitle_Langs -> List GUE.SendPrefsTitle_Langs
updateLangPrefs msg model =
  case msg of
    LangAdd ->
      let new = { lang = Just "en", official = True, original = False, latin = False }
      in if List.any (\e -> e.lang == Nothing) model
         then List.foldl (\e l -> if e.lang == Nothing && not (List.any (\x -> x.lang == Nothing) l) then l ++ [new, e] else l ++ [e]) [] model
         else model ++ [new]
    LangDel n -> delidx n model
    LangSet n s -> modidx n (\e -> { e | lang = if s == "" then Nothing else Just s }) model
    LangType n (f,r) -> modidx n (\e -> { e | official = f, original = r }) model
    LangLatin n b -> modidx n (\e -> { e | latin = b }) model

updatePrefs : PrefMsg -> GUE.SendPrefs -> GUE.SendPrefs
updatePrefs msg model =
  case msg of
    EMail n    -> { model | email = n }
    MaxSexual n-> { model | max_sexual = n }
    MaxViolence n  -> { model | max_violence = n }
    TraitsSexual b -> { model | traits_sexual = b }
    Spoilers n -> { model | spoilers  = n }
    TagsAll b  -> { model | tags_all  = b }
    TagsCont b -> { model | tags_cont = b }
    TagsEro b  -> { model | tags_ero  = b }
    TagsTech b -> { model | tags_tech = b }
    VNRelLangs l->{ model | vnrel_langs = l }
    VNRelOLang b->{ model | vnrel_olang = b }
    VNRelMTL b -> { model | vnrel_mtl = b }
    StaffEdLangs l->{ model | staffed_langs = l }
    StaffEdOLang b->{ model | staffed_olang = b }
    StaffEdUnoff b->{ model | staffed_unoff = b }
    ProdRel b  -> { model | prodrelexpand = b }
    Skin n     -> { model | skin = n }
    Css n      -> { model | customcss = n }
    NoAds b    -> { model | nodistract_noads = b }
    NoFancy b  -> { model | nodistract_nofancy = b }
    Support b  -> { model | support_enabled = b }
    PubSkin b  -> { model | pubskin_enabled = b }
    Uniname n  -> { model | uniname = n }
    TitleLang m   -> { model | title_langs    = updateLangPrefs m model.title_langs }
    AltTitleLang m-> { model | alttitle_langs = updateLangPrefs m model.alttitle_langs }
    TraitDel idx  -> { model | traits = delidx idx model.traits }

updatePass : PassMsg -> PassData -> PassData
updatePass msg model =
  case msg of
    CPass b -> { model | cpass = b }
    OPass n -> { model | opass = n }
    Pass1 n -> { model | pass1 = n }
    Pass2 n -> { model | pass2 = n }


encode : Model -> GUE.Send
encode model =
  { id       = model.id
  , username = Maybe.withDefault model.username model.nusername
  , admin    = model.admin
  , prefs    = model.prefs
  , password = Maybe.andThen (\p -> if p.cpass && p.pass1 == p.pass2 then Just { old = p.opass, new = p.pass1 } else Nothing) model.pass
  }


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Tab t   -> ({ model | tab = t }, Cmd.none)
    Invalid t  -> if model.invalidDis || model.tab == t then (model, Cmd.none) else
                  ({ model | tab = t, invalidDis = True }, Task.attempt (always InvalidEnable) (Ffi.elemCall "reportValidity" "mainform" |> Task.andThen (\_ -> Process.sleep 100)))
    InvalidEnable -> ({ model | invalidDis = False }, Cmd.none)
    Admin m -> ({ model | admin = Maybe.map (updateAdmin m) model.admin }, Cmd.none)
    Prefs m ->
      let np = Maybe.map (updatePrefs m) model.prefs
          s = Maybe.map (\x -> x.skin) >> Maybe.withDefault ""
      in ({ model | prefs = np }, if (s np) /= (s model.prefs) then skinChange (s np) else Cmd.none)
    Pass  m -> ({ model | pass  = Maybe.map (updatePass  m) model.pass, passNeq = False }, Cmd.none)
    Username s -> ({ model | nusername = s }, Cmd.none)

    TraitSearch m ->
      let (nm, c, res) = A.update traitConfig m model.traitSearch
      in case (res, model.prefs) of
        (Just t, Just p) ->
          if not t.applicable || t.hidden || List.any (\l -> l.tid == t.id) p.traits
          then ({ model | traitSearch = A.clear nm "" }, c)
          else
            let np = { p | traits = p.traits ++ [{ tid = t.id, name = t.name, group = t.group_name }] }
            in ({ model | traitSearch = A.clear nm "", prefs = Just np }, c)
        _ -> ({ model | traitSearch = nm }, c)

    Submit ->
      if Maybe.withDefault False (Maybe.map (\p -> p.cpass && p.pass1 /= p.pass2) model.pass)
      then ({ model | passNeq = True }, Cmd.none )
      else ({ model | state = Api.Loading }, GUE.send (encode model) Submitted)

    -- TODO: This reload is only necessary for the skin and customcss options to apply, but it's nicer to do that directly from JS.
    Submitted GApi.Success    -> (model, load <| "/" ++ model.id ++ "/edit")
    Submitted GApi.MailChange -> ({ model | mailConfirm = True, state = Api.Normal }, Cmd.none)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


-- Languages with different writing systems than Latin
romanizedLangs = Set.fromList [ "", "ar", "fa", "he", "hi", "ja", "ko", "ru", "sk", "th", "uk", "ur", "zh", "zh-Hans", "zh-Hant" ]


view : Model -> Html Msg
view model =
  let
    opts = model.opts
    perm b f = if opts.perm_usermod || b then f else text ""

    adminform m =
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Admin options" ] ]
      , formField "Permissions"
        [ text "Fields marked with * indicate permissions assigned to new users by default", br_ 1
        , perm False <| span [] [ inputButton "None" (Admin PermNone) [], inputButton "Default" (Admin PermDefault) [], br_ 1 ]
        , perm opts.perm_boardmod <| label [] [ inputCheck "" m.perm_board    (Admin << PermBoard),    text " board*", br_ 1 ]
        , perm opts.perm_boardmod <| label [] [ inputCheck "" m.perm_review   (Admin << PermReview),   text " review*", br_ 1 ]
        , perm False              <| label [] [ inputCheck "" m.perm_boardmod (Admin << PermBoardmod), text " boardmod", br_ 1 ]
        , perm opts.perm_dbmod    <| label [] [ inputCheck "" m.perm_edit     (Admin << PermEdit),     text " edit*", br_ 1 ]
        , perm opts.perm_dbmod    <| label [] [ inputCheck "" m.perm_imgvote  (Admin << PermImgvote),  text " imgvote* (existing votes will stop counting when unset)", br_ 1 ]
        , perm opts.perm_dbmod    <| label [] [ inputCheck "" m.perm_lengthvote(Admin<< PermLengthvote),text " lengthvote* (existing votes will stop counting when unset)", br_ 1 ]
        , perm opts.perm_tagmod   <| label [] [ inputCheck "" m.perm_tag      (Admin << PermTag),      text " tag* (existing tag votes will stop counting when unset)", br_ 1 ]
        , perm False              <| label [] [ inputCheck "" m.perm_dbmod    (Admin << PermDbmod),    text " dbmod", br_ 1 ]
        , perm False              <| label [] [ inputCheck "" m.perm_tagmod   (Admin << PermTagmod),   text " tagmod", br_ 1 ]
        , perm False              <| label [] [ inputCheck "" m.perm_usermod  (Admin << PermUsermod),  text " usermod", br_ 1 ]
        ]
      , perm False <| formField "Other" [ label [] [ inputCheck "" m.ign_votes (Admin << IgnVotes), text " Ignore votes in VN statistics" ] ]
      ]

    passform m =
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Password" ] ]
      , formField "" [ label [] [ inputCheck "" m.cpass (Pass << CPass), text " Change password" ] ]
      ] ++ if not m.cpass then [] else
        [ tr [] [ K.node "td" [colspan 2] [("pass_change", table []
          [ formField "opass::Old password" [ inputPassword "opass" m.opass (Pass << OPass) (onInvalid (Invalid Profile) :: GUE.valPasswordOld) ]
          , formField "pass1::New password" [ inputPassword "pass1" m.pass1 (Pass << Pass1) (onInvalid (Invalid Profile) :: GUE.valPasswordNew) ]
          , formField "pass2::Repeat"
            [ inputPassword "pass2" m.pass2 (Pass << Pass2) (onInvalid (Invalid Profile) :: GUE.valPasswordNew)
            , br_ 1
            , if model.passNeq
              then b [ class "standout" ] [ text "Passwords do not match" ]
              else text ""
            ]
          ])]]
        ]

    supportform m =
      if not (opts.perm_usermod || opts.nodistract_can || opts.support_can || opts.uniname_can || opts.pubskin_can) then [] else
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Supporter options⭐" ] ]
      , perm opts.nodistract_can <| formField "" [ label [] [ inputCheck "" m.nodistract_noads   (Prefs << NoAds),   text " Disable advertising and other distractions (only hides the support icons for the moment)" ] ]
      , perm opts.nodistract_can <| formField "" [ label [] [ inputCheck "" m.nodistract_nofancy (Prefs << NoFancy), text " Disable supporters badges, custom display names and profile skins" ] ]
      , perm opts.support_can    <| formField "" [ label [] [ inputCheck "" m.support_enabled    (Prefs << Support), text " Display my supporters badge" ] ]
      , perm opts.pubskin_can    <| formField "" [ label [] [ inputCheck "" m.pubskin_enabled    (Prefs << PubSkin), text " Apply my skin and custom CSS when others visit my profile" ] ]
      , perm opts.uniname_can    <| formField "uniname::Display name" [ inputText "uniname" (if m.uniname == "" then model.username else m.uniname) (Prefs << Uniname) GUE.valPrefsUniname ]
      ]

    traitsform m =
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Public traits" ] ]
      , formField "Traits"
        [ p [ style "padding-bottom" "4px" ]
          [ text "You can add ", a [ href "/i" ] [ text "character traits" ], text " to your account. These will be displayed on your public profile." ]
        , if List.isEmpty m.traits then text ""
          else table [] <| List.indexedMap (\i t -> tr []
            [ td []
              [ Maybe.withDefault (text "") <| Maybe.map (\g -> b [ class "grayedout" ] [ text <| g ++ " / " ]) t.group
              , a [ href <| "/" ++ t.tid ] [ text t.name ]
              ]
            , td [] [ inputButton "remove" (Prefs (TraitDel i)) [] ]
            ]
          ) m.traits
        , if List.length m.traits >= 100 then text ""
          else A.view traitConfig model.traitSearch [placeholder "Add trait..."]
        ]
      ]

    langprefsform m alt = table [] <|
        tfoot [] [ tr [] [ td [ colspan 5 ]
          [ if List.length m < 5
            then inputButton "Add language" LangAdd []
            else text ""
          ]
        ] ] :: List.indexedMap (\n e -> tr []
        [ td [] [ text ("#" ++ String.fromInt (n+1)) ]
        , td [] [ if not alt && e.lang == Nothing
                  then text "Original language"
                  else inputSelect "" (Maybe.withDefault "" e.lang) (LangSet n) [style "width" "200px"] ((if alt then [("", "Original language")] else []) ++ GT.languages) ]
        , td [] [ if Set.member (Maybe.withDefault "" e.lang) romanizedLangs then label [] [ inputCheck "" e.latin (LangLatin n), text " romanized" ] else text "" ]
        , td [] [ if e.lang == Nothing then text "" else inputSelect "" (e.official, e.original) (LangType n) []
                  [ ((True,True), "Only if original title"), ((True,False), "Only if official title"), ((False,False), "Include non-official titles") ] ]
        , td [] [ if not alt && e.lang == Nothing then text "" else inputButton "remove" (LangDel n) [] ]
        ]
      ) m

    prefsform m =
      [ formField "NSFW"
        [ inputSelect "" m.max_sexual (Prefs << MaxSexual) [style "width" "400px"]
          [ (-1,"Hide all images")
          , (0, "Hide sexually suggestive or explicit images")
          , (1, "Hide only sexually explicit images")
          , (2, "Don't hide suggestive or explicit images")
          ]
        , br [] []
        , if m.max_sexual == -1 then text "" else
          inputSelect "" m.max_violence (Prefs << MaxViolence) [style "width" "400px"]
          [ (0, "Hide violent or brutal images")
          , (1, "Hide only brutal images")
          , (2, "Don't hide violent or brutal images")
          ]
        ]
      , formField "" [ label [] [ inputCheck "" m.traits_sexual (Prefs << TraitsSexual), text " Show sexual traits by default on character pages" ] ]
      , formField "spoil::Default spoiler level"
        [ inputSelect "spoil" m.spoilers (Prefs << Spoilers) []
          [ (0, "Hide spoilers")
          , (1, "Show only minor spoilers")
          , (2, "Show all spoilers")
          ]
        ]
      , formField "prodrel::Default producer tab"
        [ inputSelect "prodrel" m.prodrelexpand (Prefs << ProdRel) [] [ (False, "Visual Novels"), (True, "Releases") ] ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Language" ] ]
      , formField "Titles" <|
        [ Html.map (Prefs << TitleLang) (langprefsform m.title_langs False) ]
      , formField "Alternative titles" <|
        [ text "The alternative title is displayed below the main title and as tooltip for links."
        , br [] []
        , Html.map (Prefs << AltTitleLang) (langprefsform m.alttitle_langs True)
        , br [] []
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Visual novel pages" ] ]
      , formField "Tags" [ label [] [ inputCheck "" m.tags_all (Prefs << TagsAll), text " Show all tags by default (don't summarize)" ] ]
      , formField ""
        [ text "Default tag categories:", br_ 1
        , label [] [ inputCheck "" m.tags_cont (Prefs << TagsCont), text " Content" ], br_ 1
        , label [] [ inputCheck "" m.tags_ero  (Prefs << TagsEro ), text " Sexual content" ], br_ 1
        , label [] [ inputCheck "" m.tags_tech (Prefs << TagsTech), text " Technical" ]
        ]
      , formField "Releases"
        [ text "Expand releases for the following languages by default", br_ 1
        , select [ tabindex 10, multiple True, onInputMultiple (Prefs << VNRelLangs), style "height" "200px" ]
          <| List.map (\(k,v) -> option [ value k, selected (List.member k m.vnrel_langs) ] [ text v ]) GT.languages
        , br_ 1
        , label [] [ inputCheck "" m.vnrel_olang (Prefs << VNRelOLang), text " Always expand original language" ], br_ 1
        , label [] [ inputCheck "" m.vnrel_mtl   (Prefs << VNRelMTL  ), text " Expand machine translations" ]
        ]
      , formField "Staff"
        [ text "Expand editions for the following languages by default", br_ 1
        , select [ tabindex 10, multiple True, onInputMultiple (Prefs << StaffEdLangs), style "height" "200px" ]
          <| List.map (\(k,v) -> option [ value k, selected (List.member k m.staffed_langs) ] [ text v ]) GT.languages
        , br_ 1
        , label [] [ inputCheck "" m.staffed_olang (Prefs << StaffEdOLang), text " Always expand original edition" ], br_ 1
        , label [] [ inputCheck "" m.staffed_unoff (Prefs << StaffEdUnoff), text " Expand unofficial editions" ]
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Theme" ] ]
      , formField "skin::Skin" [ inputSelect "skin" m.skin (Prefs << Skin) [ style "width" "300px" ] GT.skins ]
      , formField "css::Custom CSS" [ inputTextArea "css" m.customcss (Prefs << Css) ([ rows 5, cols 60 ] ++ GUE.valPrefsCustomcss) ]
      ]

  in form_ "mainform" Submit (model.state == Api.Loading)
    [ if model.prefs == Nothing then text "" else div [ class "maintabs left" ]
      [ ul []
        [ li [ classList [("tabselected", model.tab == Profile    )] ] [ a [ href "#", onClickD (Tab Profile    ) ] [ text "Account" ] ]
        , li [ classList [("tabselected", model.tab == Preferences)] ] [ a [ href "#", onClickD (Tab Preferences) ] [ text "Display preferences" ] ]
        ]
      ]
    , div [ class "mainbox", classList [("hidden", model.tab /= Profile    )] ]
      [ h1 [] [ text "Account" ]
      , table [ class "formtable" ] <|
        [ formField "Username"
          [ text model.username, text " "
          , if model.prefs == Nothing then text "" else label []
            [ inputCheck "" (model.nusername /= Nothing) (\b -> Username <| if b then Just model.username else Nothing)
            , text " change" ]
          ]
        , Maybe.withDefault (text "") <| Maybe.map (\u ->
           tr [] [ K.node "td" [colspan 2] [("username_change", table []
            [ formField "username::New username"
              [ inputText "username" u (Username << Just) (onInvalid (Invalid Profile) :: GUE.valUsername)
              , br [] []
              , text "You may only change your username once a day. Your old username(s) will be displayed on your profile for a month after the change."
              ]
            ])] ]
          ) model.nusername
        , Maybe.withDefault (text "") <| Maybe.map (\m ->
            formField "email::E-Mail" [ inputText "email" m.email (Prefs << EMail) (onInvalid (Invalid Profile) :: GUE.valPrefsEmail) ]
          ) model.prefs
        ]
        ++ (Maybe.withDefault [] (Maybe.map passform model.pass))
        ++ (Maybe.withDefault [] (Maybe.map adminform model.admin))
        ++ (Maybe.withDefault [] (Maybe.map supportform model.prefs))
        ++ (Maybe.withDefault [] (Maybe.map traitsform model.prefs))
      ]
    , div [ class "mainbox", classList [("hidden", model.tab /= Preferences)] ]
      [ h1 [] [ text "Display preferences" ]
      , table [ class "formtable" ] <| Maybe.withDefault [] (Maybe.map prefsform model.prefs)
      ]
    , div [ class "mainbox" ]
      [ fieldset [ class "submit" ] [ submitButton "Submit" model.state (not model.passNeq) ]
      , if not model.mailConfirm then text "" else
          div [ class "notice" ]
          [ text "A confirmation email has been sent to your new address. Your address will be updated after following the instructions in that mail." ]
      ]
    ]
