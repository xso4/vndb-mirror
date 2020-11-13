module TagEdit exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Api as Api
import Lib.Util exposing (..)
import Lib.Autocomplete as A
import Lib.Ffi as Ffi
import Gen.Api as GApi
import Gen.Types exposing (tagCategories)
import Gen.TagEdit as GTE


main : Program GTE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type alias Model =
  { formstate    : Api.State
  , id           : Maybe Int
  , name         : String
  , aliases      : String
  , state        : Int
  , cat          : String
  , description  : TP.Model
  , searchable   : Bool
  , applicable   : Bool
  , defaultspoil : Int
  , parents      : List GTE.RecvParents
  , parentAdd    : A.Model GApi.ApiTagResult
  , addedby      : String
  , wipevotes    : Bool
  , merge        : List GTE.RecvParents
  , mergeAdd     : A.Model GApi.ApiTagResult
  , canMod       : Bool
  , dupNames     : List GApi.ApiDupNames
  }


init : GTE.Recv -> Model
init d =
  { formstate    = Api.Normal
  , id           = d.id
  , name         = d.name
  , aliases      = String.join "\n" d.aliases
  , state        = d.state
  , cat          = d.cat
  , description  = TP.bbcode d.description
  , searchable   = d.searchable
  , applicable   = d.applicable
  , defaultspoil = d.defaultspoil
  , parents      = d.parents
  , parentAdd    = A.init ""
  , addedby      = d.addedby
  , wipevotes    = False
  , merge        = []
  , mergeAdd     = A.init ""
  , canMod       = d.can_mod
  , dupNames     = []
  }


splitAliases : String -> List String
splitAliases l = String.lines l |> List.map String.trim |> List.filter (\s -> s /= "")

findDup : Model -> String -> List GApi.ApiDupNames
findDup model a = List.filter (\t -> String.toLower t.name == String.toLower a) model.dupNames

isValid : Model -> Bool
isValid model = not (List.any (findDup model >> List.isEmpty >> not) (model.name :: splitAliases model.aliases))

parentConfig : A.Config Msg GApi.ApiTagResult
parentConfig = { wrap = ParentSearch, id = "parentadd", source = A.tagSource }

mergeConfig : A.Config Msg GApi.ApiTagResult
mergeConfig = { wrap = MergeSearch, id = "mergeadd", source = A.tagSource }


encode : Model -> GTE.Send
encode m =
  { id           = m.id
  , name         = m.name
  , aliases      = splitAliases m.aliases
  , state        = m.state
  , cat          = m.cat
  , description  = m.description.data
  , searchable   = m.searchable
  , applicable   = m.applicable
  , defaultspoil = m.defaultspoil
  , parents      = List.map (\l -> {id=l.id}) m.parents
  , wipevotes    = m.wipevotes
  , merge        = List.map (\l -> {id=l.id}) m.merge
  }


type Msg
  = Name String
  | Aliases String
  | State Int
  | Searchable Bool
  | Applicable Bool
  | Cat String
  | DefaultSpoil Int
  | Description TP.Msg
  | ParentDel Int
  | ParentSearch (A.Msg GApi.ApiTagResult)
  | WipeVotes Bool
  | MergeDel Int
  | MergeSearch (A.Msg GApi.ApiTagResult)
  | Submit
  | Submitted (GApi.Response)


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Name s        -> ({ model | name = s }, Cmd.none)
    Aliases s     -> ({ model | aliases = String.replace "," "\n" s }, Cmd.none)
    State n       -> ({ model | state = n }, Cmd.none)
    Searchable b  -> ({ model | searchable = b }, Cmd.none)
    Applicable b  -> ({ model | applicable = b }, Cmd.none)
    Cat s         -> ({ model | cat = s }, Cmd.none)
    DefaultSpoil n-> ({ model | defaultspoil = n }, Cmd.none)
    WipeVotes b   -> ({ model | wipevotes = b }, Cmd.none)
    Description m -> let (nm,nc) = TP.update m model.description in ({ model | description = nm }, Cmd.map Description nc)

    ParentDel i   -> ({ model | parents = delidx i model.parents }, Cmd.none)
    ParentSearch m ->
      let (nm, c, res) = A.update parentConfig m model.parentAdd
      in case res of
        Nothing -> ({ model | parentAdd = nm }, c)
        Just p  ->
          if List.any (\e -> e.id == p.id) model.parents
          then ({ model | parentAdd = nm }, c)
          else ({ model | parentAdd = A.clear nm "", parents = model.parents ++ [{ id = p.id, name = p.name}] }, c)

    MergeDel i   -> ({ model | merge = delidx i model.merge }, Cmd.none)
    MergeSearch m ->
      let (nm, c, res) = A.update mergeConfig m model.mergeAdd
      in case res of
        Nothing -> ({ model | mergeAdd = nm }, c)
        Just p  -> ({ model | mergeAdd = A.clear nm "", merge = model.merge ++ [{ id = p.id, name = p.name}] }, c)

    Submit -> ({ model | formstate = Api.Loading }, GTE.send (encode model) Submitted)
    Submitted (GApi.DupNames l) -> ({ model | dupNames = l, formstate = Api.Normal }, Cmd.none)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | formstate = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ "" Submit (model.formstate == Api.Loading)
  [ div [ class "mainbox" ]
    [ h1 [] [ text <| if model.id == Nothing then "Submit new tag" else "Edit tag" ]
    , table [ class "formtable" ] <|
      [ if model.id == Nothing then text "" else
        formField "Added by" [ span [ Ffi.innerHtml model.addedby ] [], br_ 2 ]
      , formField "name::Primary name" [ inputText "name" model.name Name GTE.valName ]
      , formField "aliases::Aliases"
        -- BUG: Textarea doesn't validate the maxlength and patterns for aliases, we don't have a client-side fallback check either.
        [ inputTextArea "aliases" model.aliases Aliases []
        , let dups = List.concatMap (findDup model) (model.name :: splitAliases model.aliases)
          in if List.isEmpty dups
             then span [] [ br [] [], text "Tag name and aliases must be unique and self-describing." ]
             else div []
             [ b [ class "standout" ] [ text "The following tag names are already present in the database:" ]
             , ul [] <| List.map (\t ->
                 li [] [ a [ href ("/g"++String.fromInt t.id) ] [ text t.name ] ]
               ) dups
             ]
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , if not model.canMod then text "" else
        formField "state::State" [ inputSelect "state" model.state State GTE.valState
          [ (0, "Awaiting Moderation")
          , (1, "Deleted/hidden")
          , (2, "Approved")
          ]
        ]
      , if not model.canMod then text "" else
        formField "" [ label [] [ inputCheck "" model.searchable Searchable, text " Searchable (people can use this tag to find VNs)" ] ]
      , if not model.canMod then text "" else
        formField "" [ label [] [ inputCheck "" model.applicable Applicable, text " Applicable (people can apply this tag to VNs)" ] ]
      , formField "cat::Category" [ inputSelect "cat" model.cat Cat GTE.valCat tagCategories ]
      , formField "defaultspoil::Default spoiler level" [ inputSelect "defaultspoil" model.defaultspoil DefaultSpoil GTE.valDefaultspoil 
        [ (0, "No spoiler")
        , (1, "Minor spoiler")
        , (2, "Major spoiler")
        ] ]
      , text "" -- aliases
      , formField "description::Description"
        [ TP.view "description" model.description Description 700 ([rows 12, cols 50] ++ GTE.valDescription) []
        , text "What should the tag be used for? Having a good description helps users choose which tags to link to a VN."
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "Parent tags"
        [ table [ class "compact" ] <| List.indexedMap (\i p -> tr []
            [ td [ style "text-align" "right" ] [ b [ class "grayedout" ] [ text <| "g" ++ String.fromInt p.id ++ ":" ] ]
            , td [] [ a [ href <| "/g" ++ String.fromInt p.id ] [ text p.name ] ]
            , td [] [ inputButton "remove" (ParentDel i) [] ]
            ]
          ) model.parents
        , A.view parentConfig model.parentAdd [placeholder "Add parent tag..."]
        ]
      ]
      ++ if not model.canMod || model.id == Nothing then [] else
      [ tr [ class "newpart" ] [ td [ colspan 2 ] [ text "DANGER ZONE" ] ]
      , formField ""
        [ inputCheck "" model.wipevotes WipeVotes
        , text " Delete all direct votes on this tag. WARNING: cannot be undone!", br [] []
        , b [ class "grayedout" ] [ text "Does not affect votes on child tags. Old votes may still show up for 24 hours due to database caching." ]
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "Merge votes"
        [ text "All direct votes on the listed tags will be moved to this tag. WARNING: cannot be undone!", br [] []
        , table [ class "compact" ] <| List.indexedMap (\i p -> tr []
            [ td [ style "text-align" "right" ] [ b [ class "grayedout" ] [ text <| "g" ++ String.fromInt p.id ++ ":" ] ]
            , td [] [ a [ href <| "/g" ++ String.fromInt p.id ] [ text p.name ] ]
            , td [] [ inputButton "remove" (MergeDel i) [] ]
            ]
          ) model.merge
        , A.view mergeConfig model.mergeAdd [placeholder "Add tag to merge..."]
        ]
      ]
    ]
  , div [ class "mainbox" ]
    [ fieldset [ class "submit" ] [ submitButton "Submit" model.formstate (isValid model) ] ]
  ]
