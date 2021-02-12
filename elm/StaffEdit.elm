module StaffEdit exposing (main)

import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Lib.Editsum as Editsum
import Gen.StaffEdit as GSE
import Gen.Types as GT
import Gen.Api as GApi


main : Program GSE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { state       : Api.State
  , editsum     : Editsum.Model
  , alias       : List GSE.RecvAlias
  , aliasDup    : Bool
  , aid         : Int
  , desc        : TP.Model
  , gender      : String
  , lang        : String
  , l_site      : String
  , l_wikidata  : Maybe Int
  , l_twitter   : String
  , l_anidb     : Maybe Int
  , l_pixiv     : Int
  , id          : Maybe String
  }


init : GSE.Recv -> Model
init d =
  { state       = Api.Normal
  , editsum     = { authmod = d.authmod, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden }
  , alias       = d.alias
  , aliasDup    = False
  , aid         = d.aid
  , desc        = TP.bbcode d.desc
  , gender      = d.gender
  , lang        = d.lang
  , l_site      = d.l_site
  , l_wikidata  = d.l_wikidata
  , l_twitter   = d.l_twitter
  , l_anidb     = d.l_anidb
  , l_pixiv     = d.l_pixiv
  , id          = d.id
  }


encode : Model -> GSE.Send
encode model =
  { id          = model.id
  , editsum     = model.editsum.editsum.data
  , hidden      = model.editsum.hidden
  , locked      = model.editsum.locked
  , aid         = model.aid
  , alias       = List.map (\e -> { aid = e.aid, name = e.name, original = e.original }) model.alias
  , desc        = model.desc.data
  , gender      = model.gender
  , lang        = model.lang
  , l_site      = model.l_site
  , l_wikidata  = model.l_wikidata
  , l_twitter   = model.l_twitter
  , l_anidb     = model.l_anidb
  , l_pixiv     = model.l_pixiv
  }


newAid : Model -> Int
newAid model =
  let id = Maybe.withDefault 0 <| List.minimum <| List.map .aid model.alias
  in if id >= 0 then -1 else id - 1


type Msg
  = Editsum Editsum.Msg
  | Submit
  | Submitted GApi.Response
  | Lang String
  | Gender String
  | Website String
  | LWikidata (Maybe Int)
  | LTwitter String
  | LAnidb String
  | LPixiv String
  | Desc TP.Msg
  | AliasDel Int
  | AliasName Int String
  | AliasOrig Int String
  | AliasMain Int Bool
  | AliasAdd


validate : Model -> Model
validate model = { model | aliasDup = hasDuplicates <| List.map (\e -> (e.name, e.original)) model.alias }


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Editsum m  -> let (nm,nc) = Editsum.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)
    Lang s     -> ({ model | lang      = s }, Cmd.none)
    Gender s   -> ({ model | gender    = s }, Cmd.none)
    Website s  -> ({ model | l_site    = s }, Cmd.none)
    LWikidata n-> ({ model | l_wikidata= n }, Cmd.none)
    LTwitter s -> ({ model | l_twitter = s }, Cmd.none)
    LAnidb s   -> ({ model | l_anidb   = if s == "" then Nothing else String.toInt s }, Cmd.none)
    LPixiv s   -> ({ model | l_pixiv   = Maybe.withDefault model.l_pixiv (String.toInt s) }, Cmd.none)
    Desc m     -> let (nm,nc) = TP.update m model.desc in ({ model | desc = nm }, Cmd.map Desc nc)

    AliasDel i    -> (validate { model | alias = delidx i model.alias }, Cmd.none)
    AliasName i s -> (validate { model | alias = modidx i (\e -> { e | name     = s }) model.alias }, Cmd.none)
    AliasOrig i s -> (validate { model | alias = modidx i (\e -> { e | original = s }) model.alias }, Cmd.none)
    AliasMain n _ -> ({ model | aid = n }, Cmd.none)
    AliasAdd      -> ({ model | alias = model.alias ++ [{ aid = newAid model, name = "", original = "", inuse = False, wantdel = False }] }, Cmd.none)

    Submit -> ({ model | state = Api.Loading }, GSE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


isValid : Model -> Bool
isValid model = not (model.aliasDup || List.any (\l -> l.name == l.original) model.alias)


view : Model -> Html Msg
view model =
  let
    nameEntry n e =
      tr []
      [ td [ class "tc_id" ] [ inputRadio "main" (e.aid == model.aid) (AliasMain e.aid) ]
      , td [ class "tc_name" ] [ inputText "" e.name (AliasName n) GSE.valAliasName ]
      , td [ class "tc_original" ]
        [ inputText "" e.original (AliasOrig n) GSE.valAliasOriginal
        , if e.name /= "" && e.name == e.original then b [ class "standout" ] [ text "May not be the same as Name (romaji)" ] else text ""
        ]
      , td [ class "tc_add" ]
        [ if model.aid == e.aid then b [ class "grayedout" ] [ text " primary" ]
          else if e.wantdel then b [ class "standout" ] [ text " still referenced" ]
          else if e.inuse then b [ class "grayedout" ] [ text " referenced" ]
          else inputButton "remove" (AliasDel n) []
        ]
      ]

    names =
      table [ class "names" ] <|
      [ thead []
        [ tr []
          [ td [ class "tc_id" ] []
          , td [ class "tc_name" ] [ text "Name (romaji)" ]
          , td [ class "tc_original" ] [ text "Original" ]
          , td [] []
          ]
        ]
      ] ++ List.indexedMap nameEntry model.alias ++
      [ tr [ class "alias_new" ]
        [ td [] []
        , td [ colspan 3 ]
          [ if not model.aliasDup then text ""
            else b [ class "standout" ] [ text "The list contains duplicate aliases.", br_ 1 ]
          , a [ onClick AliasAdd ] [ text "Add alias" ]
          ]
        ]
      ]

  in
    form_ "" Submit (model.state == Api.Loading)
    [ div [ class "mainbox staffedit" ]
      [ h1 [] [ text "General info" ]
      , table [ class "formtable" ]
        [ formField "Names" [ names, br_ 1 ]
        , formField "desc::Biography" [ TP.view "desc" model.desc Desc 500 GSE.valDesc [ b [ class "standout" ] [ text "English please!" ] ] ]
        , formField "gender::Gender" [ inputSelect "gender" model.gender Gender []
          [ ("unknown", "Unknown or N/A")
          , ("f",       "Female")
          , ("m",       "Male")
          ] ]
        , formField "lang::Primary Language" [ inputSelect "lang" model.lang Lang [] GT.languages ]
        , formField "l_site::Official page" [ inputText "l_site" model.l_site Website (style "width" "400px" :: GSE.valL_Site) ]
        , formField "l_wikidata::Wikidata ID" [ inputWikidata "l_wikidata" model.l_wikidata LWikidata [] ]
        , formField "l_twitter::Twitter username" [ inputText "l_twitter" model.l_twitter LTwitter GSE.valL_Twitter ]
        , formField "l_anidb::AniDB Creator ID" [ inputText "l_anidb" (Maybe.withDefault "" (Maybe.map String.fromInt model.l_anidb)) LAnidb GSE.valL_Anidb ]
        , formField "l_pixiv::Pixiv ID" [ inputText "l_pixiv" (if model.l_pixiv == 0 then "" else String.fromInt model.l_pixiv) LPixiv GSE.valL_Pixiv ]
        ]
      ]
    , div [ class "mainbox" ]
      [ fieldset [ class "submit" ]
        [ Html.map Editsum (Editsum.view model.editsum)
        , submitButton "Submit" model.state (isValid model)
        ]
      ]
    ]
