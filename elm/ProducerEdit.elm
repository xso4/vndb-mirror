module ProducerEdit exposing (main)

import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Autocomplete as A
import Lib.Api as Api
import Lib.Editsum as Editsum
import Gen.Producers as GP
import Gen.ProducerEdit as GPE
import Gen.Types as GT
import Gen.Api as GApi


main : Program GPE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

type alias Model =
  { state       : Api.State
  , editsum     : Editsum.Model
  , ptype       : String
  , name        : String
  , latin       : Maybe String
  , alias       : String
  , lang        : String
  , website     : String
  , lWikidata   : Maybe Int
  , description : TP.Model
  , rel         : List GPE.RecvRelations
  , relSearch   : A.Model GApi.ApiProducerResult
  , id          : Maybe String
  , dupCheck    : Bool
  , dupProds    : List GApi.ApiProducerResult
  }


init : GPE.Recv -> Model
init d =
  { state       = Api.Normal
  , editsum     = { authmod = d.authmod, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden, hasawait = False }
  , ptype       = d.ptype
  , name        = d.name
  , latin       = d.latin
  , alias       = d.alias
  , lang        = d.lang
  , website     = d.website
  , lWikidata   = d.l_wikidata
  , description = TP.bbcode d.description
  , rel         = d.relations
  , relSearch   = A.init ""
  , id          = d.id
  , dupCheck    = False
  , dupProds    = []
  }


encode : Model -> GPE.Send
encode model =
  { id          = model.id
  , editsum     = model.editsum.editsum.data
  , hidden      = model.editsum.hidden
  , locked      = model.editsum.locked
  , ptype       = model.ptype
  , name        = model.name
  , latin       = model.latin
  , alias       = model.alias
  , lang        = model.lang
  , website     = model.website
  , l_wikidata  = model.lWikidata
  , description = model.description.data
  , relations   = List.map (\p -> { pid = p.pid, relation = p.relation }) model.rel
  }

prodConfig : A.Config Msg GApi.ApiProducerResult
prodConfig = { wrap = RelSearch, id = "relationadd", source = A.producerSource }

type Msg
  = Editsum Editsum.Msg
  | Submit
  | Submitted GApi.Response
  | PType String
  | Name String
  | Latin String
  | Alias String
  | Lang String
  | Website String
  | LWikidata (Maybe Int)
  | Desc TP.Msg
  | RelDel Int
  | RelRel Int String
  | RelSearch (A.Msg GApi.ApiProducerResult)
  | DupSubmit
  | DupResults GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Editsum m  -> let (nm,nc) = Editsum.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)
    PType s    -> ({ model | ptype    = s }, Cmd.none)
    Name s     -> ({ model | name     = s, dupProds = [] }, Cmd.none)
    Latin s    -> ({ model | latin    = if s == "" then Nothing else Just s, dupProds = [] }, Cmd.none)
    Alias s    -> ({ model | alias    = s, dupProds = [] }, Cmd.none)
    Lang s     -> ({ model | lang     = s }, Cmd.none)
    Website s  -> ({ model | website  = s }, Cmd.none)
    LWikidata n-> ({ model | lWikidata = n }, Cmd.none)
    Desc m     -> let (nm,nc) = TP.update m model.description in ({ model | description = nm }, Cmd.map Desc nc)

    RelDel idx        -> ({ model | rel = delidx idx model.rel }, Cmd.none)
    RelRel idx rel    -> ({ model | rel = modidx idx (\p -> { p | relation = rel }) model.rel }, Cmd.none)
    RelSearch m ->
      let (nm, c, res) = A.update prodConfig m model.relSearch
      in case res of
        Nothing -> ({ model | relSearch = nm }, c)
        Just p ->
          if List.any (\l -> l.pid == p.id) model.rel
          then ({ model | relSearch = A.clear nm "" }, c)
          else ({ model | relSearch = A.clear nm "", rel = model.rel ++ [{ pid = p.id, name = p.name, altname = p.altname, relation = "old" }] }, c)

    DupSubmit ->
      if List.isEmpty model.dupProds
      then ({ model | state = Api.Loading }, GP.send { search = model.name :: Maybe.withDefault "" model.latin :: String.lines model.alias } DupResults)
      else ({ model | dupCheck = True, dupProds = [] }, Cmd.none)
    DupResults (GApi.ProducerResult prods) ->
      if List.isEmpty prods
      then ({ model | state = Api.Normal, dupCheck = True, dupProds = [] }, Cmd.none)
      else ({ model | state = Api.Normal, dupProds = prods }, Cmd.none)
    DupResults r -> ({ model | state = Api.Error r }, Cmd.none)

    Submit -> ({ model | state = Api.Loading }, GPE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


isValid : Model -> Bool
isValid model = not
  (  (model.name /= "" && Just model.name == model.latin)
  || hasDuplicates (List.map (\p -> p.pid) model.rel)
  )


view : Model -> Html Msg
view model =
  let
    titles =
      [ formField "name::Name (original)" [ inputText "name" model.name Name (style "width" "500px" :: GPE.valName) ]
      , if not (model.latin /= Nothing || containsNonLatin model.name) then text "" else
        formField "latin::Name (latin)"
        [ inputText "latin" (Maybe.withDefault "" model.latin) Latin (style "width" "500px" :: placeholder "Romanization" :: GPE.valLatin)
        , case model.latin of
            Just s -> if containsNonLatin s
                      then b [] [ br [] [], text "Romanization should only consist of characters in the latin alphabet." ] else text ""
            Nothing -> text ""
        ]
      , formField "alias::Aliases"
        [ inputTextArea "alias" model.alias Alias (rows 3 :: GPE.valAlias)
        , br [] []
        , if hasDuplicates <| String.lines <| String.toLower model.alias
          then b [] [ text "List contains duplicate aliases.", br [] [] ]
          else text ""
        , text "(Un)official aliases, separated by a newline."
        ]
      ]

    geninfo =
      [ formField "ptype::Type" [ inputSelect "ptype" model.ptype PType [] GT.producerTypes ] ]
      ++ titles ++
      [ formField "lang::Primary language" [ inputSelect "lang" model.lang Lang [] locLangs ]
      , formField "website::Website" [ inputText "website" model.website Website GPE.valWebsite ]
      , formField "l_wikidata::Wikidata ID" [ inputWikidata "l_wikidata" model.lWikidata LWikidata [] ]
      , formField "desc::Description"
        [ TP.view "desc" model.description Desc 600 (style "height" "180px" :: GPE.valDescription) [ b [] [ text "English please!" ] ] ]

      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Database relations" ] ]
      , formField "Related producers"
        [ if List.isEmpty model.rel then text ""
          else table [] <| List.indexedMap (\i p -> tr []
            [ td [] [ inputSelect "" p.relation (RelRel i) [] GT.producerRelations ]
            , td [] [ small [] [ text <| p.pid ++ ": " ], a [ href <| "/" ++ p.pid, title (Maybe.withDefault "" p.altname) ] [ text p.name ] ]
            , td [] [ inputButton "remove" (RelDel i) [] ]
            ]
          ) model.rel
        , A.view prodConfig model.relSearch [placeholder "Add Producer..."]
        ]
      ]

    newform () =
      form_ "" DupSubmit (model.state == Api.Loading)
      [ div [ class "mainbox" ] [ h1 [] [ text "Add a new producer" ], table [ class "formtable" ] titles ]
      , div [ class "mainbox" ]
        [ if List.isEmpty model.dupProds then text "" else
          div []
          [ h1 [] [ text "Possible duplicates" ]
          , text "The following is a list of producers that match the name(s) you gave. "
          , text "Please check this list to avoid creating a duplicate producer entry. "
          , text "Be especially wary of items that have been deleted! To see why an entry has been deleted, click on its title."
          , ul [] <| List.map (\p -> li [] [ a [ href <| "/" ++ p.id ] [ text p.name ] ]) model.dupProds
          ]
        , fieldset [ class "submit" ] [ submitButton (if List.isEmpty model.dupProds then "Continue" else "Continue anyway") model.state (isValid model) ]
        ]
      ]

    fullform () =
      form_ "" Submit (model.state == Api.Loading)
      [ div [ class "mainbox" ] [ h1 [] [ text "Edit producer" ], table [ class "formtable" ] geninfo ]
      , div [ class "mainbox" ] [ fieldset [ class "submit" ]
          [ Html.map Editsum (Editsum.view model.editsum)
          , submitButton "Submit" model.state (isValid model)
          ]
        ]
      ]
  in if model.id == Nothing && not model.dupCheck then newform () else fullform ()
