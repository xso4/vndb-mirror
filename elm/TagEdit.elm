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
import Lib.Editsum as Editsum
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
  { state        : Api.State
  , editsum      : Editsum.Model
  , id           : Maybe String
  , name         : String
  , alias        : String
  , cat          : String
  , description  : TP.Model
  , searchable   : Bool
  , applicable   : Bool
  , defaultspoil : Int
  , parents      : List GTE.RecvParents
  , parentAdd    : A.Model GApi.ApiTagResult
  , wipevotes    : Bool
  , merge        : List GTE.RecvMerge
  , mergeAdd     : A.Model GApi.ApiTagResult
  , dupNames     : List GApi.ApiDupNames
  }


init : GTE.Recv -> Model
init d =
  { state        = Api.Normal
  , editsum      = { authmod = d.authmod, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden, hasawait = True }
  , id           = d.id
  , name         = d.name
  , alias        = d.alias
  , cat          = d.cat
  , description  = TP.bbcode d.description
  , searchable   = d.searchable
  , applicable   = d.applicable
  , defaultspoil = d.defaultspoil
  , parents      = d.parents
  , parentAdd    = A.init ""
  , wipevotes    = False
  , merge        = []
  , mergeAdd     = A.init ""
  , dupNames     = []
  }


splitAliases : String -> List String
splitAliases l = String.lines l |> List.map String.trim |> List.filter (\s -> s /= "")

findDup : Model -> String -> List GApi.ApiDupNames
findDup model a = List.filter (\t -> String.toLower t.name == String.toLower a) model.dupNames

isValid : Model -> Bool
isValid model = not (List.any (findDup model >> List.isEmpty >> not) (model.name :: splitAliases model.alias))

parentConfig : A.Config Msg GApi.ApiTagResult
parentConfig = { wrap = ParentSearch, id = "parentadd", source = A.tagSource }

mergeConfig : A.Config Msg GApi.ApiTagResult
mergeConfig = { wrap = MergeSearch, id = "mergeadd", source = A.tagSource }


encode : Model -> GTE.Send
encode m =
  { id           = m.id
  , editsum      = m.editsum.editsum.data
  , hidden       = m.editsum.hidden
  , locked       = m.editsum.locked
  , name         = m.name
  , alias        = m.alias
  , cat          = m.cat
  , description  = m.description.data
  , searchable   = m.searchable
  , applicable   = m.applicable
  , defaultspoil = m.defaultspoil
  , parents      = List.map (\l -> {parent=l.parent, main=l.main}) m.parents
  , wipevotes    = m.wipevotes
  , merge        = List.map (\l -> {id=l.id}) m.merge
  }


type Msg
  = Name String
  | Alias String
  | Searchable Bool
  | Applicable Bool
  | Cat String
  | DefaultSpoil Int
  | Description TP.Msg
  | Editsum Editsum.Msg
  | ParentMain Int Bool
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
    Alias s       -> ({ model | alias = String.replace "," "\n" s }, Cmd.none)
    Searchable b  -> ({ model | searchable = b }, Cmd.none)
    Applicable b  -> ({ model | applicable = b }, Cmd.none)
    Cat s         -> ({ model | cat = s }, Cmd.none)
    DefaultSpoil n-> ({ model | defaultspoil = n }, Cmd.none)
    WipeVotes b   -> ({ model | wipevotes = b }, Cmd.none)
    Description m -> let (nm,nc) = TP.update m model.description in ({ model | description = nm }, Cmd.map Description nc)
    Editsum m     -> let (nm,nc) = Editsum.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)

    ParentMain i _-> ({ model | parents = List.indexedMap (\n p -> { p | main = i == n }) model.parents }, Cmd.none)
    ParentDel i   ->
      let np = delidx i model.parents
          nnp = if List.any (\p -> p.main) np then np else List.indexedMap (\n p -> { p | main = n == 0 }) np
      in ({ model | parents = nnp }, Cmd.none)
    ParentSearch m ->
      let (nm, c, res) = A.update parentConfig m model.parentAdd
      in case res of
        Nothing -> ({ model | parentAdd = nm }, c)
        Just p  ->
          if List.any (\e -> e.parent == p.id) model.parents
          then ({ model | parentAdd = nm }, c)
          else ({ model | parentAdd = A.clear nm "", parents = model.parents ++ [{ parent = p.id, main = List.isEmpty model.parents, name = p.name}] }, c)

    MergeDel i   -> ({ model | merge = delidx i model.merge }, Cmd.none)
    MergeSearch m ->
      let (nm, c, res) = A.update mergeConfig m model.mergeAdd
      in case res of
        Nothing -> ({ model | mergeAdd = nm }, c)
        Just p  -> ({ model | mergeAdd = A.clear nm "", merge = model.merge ++ [{ id = p.id, name = p.name}] }, c)

    Submit -> ({ model | state = Api.Loading }, GTE.send (encode model) Submitted)
    Submitted (GApi.DupNames l) -> ({ model | dupNames = l, state = Api.Normal }, Cmd.none)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
  [ article []
    [ h1 [] [ text <| if model.id == Nothing then "Submit new tag" else "Edit tag" ]
    , table [ class "formtable" ] <|
      [ formField "name::Primary name" [ inputText "name" model.name Name GTE.valName ]
      , formField "alias::Aliases"
        -- BUG: Textarea doesn't validate the maxlength and patterns for aliases, we don't have a client-side fallback check either.
        [ inputTextArea "alias" model.alias Alias []
        , let dups = List.concatMap (findDup model) (model.name :: splitAliases model.alias)
          in if List.isEmpty dups
             then span [] [ br [] [], text "Tag name and aliases must be unique and self-describing." ]
             else div []
             [ b [] [ text "The following tag names are already present in the database:" ]
             , ul [] <| List.map (\t ->
                 li [] [ a [ href ("/"++t.id) ] [ text t.name ] ]
               ) dups
             ]
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "" [ label [] [ inputCheck "" model.searchable Searchable, text " Searchable (people can use this tag to find VNs)" ] ]
      , formField "" [ label [] [ inputCheck "" model.applicable Applicable, text " Applicable (people can apply this tag to VNs)" ] ]
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
            [ td [ style "text-align" "right" ] [ small [] [ text <| p.parent ++ ":" ] ]
            , td [] [ a [ href <| "/" ++ p.parent ] [ text p.name ] ]
            , td [] [ label [] [ inputRadio "parentprimary" p.main (ParentMain i), text " primary" ] ]
            , td [] [ inputButton "remove" (ParentDel i) [] ]
            ]
          ) model.parents
        , A.view parentConfig model.parentAdd [placeholder "Add parent tag..."]
        ]
      ]
      ++ if not model.editsum.authmod || model.id == Nothing then [] else
      [ tr [ class "newpart" ] [ td [ colspan 2 ]
        [ text "DANGER ZONE"
        , small [] [ text " (The options in this section are not visible in the edit history. Your edit summary will not be visible anywhere unless you also changed something in the above fields)" ]
        , br_ 2
        ] ]
      , formField ""
        [ inputCheck "" model.wipevotes WipeVotes
        , text " Delete all direct votes on this tag. WARNING: cannot be undone!", br [] []
        , small [] [ text "Does not affect votes on child tags. Old votes may still show up for 24 hours due to database caching." ]
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "Merge votes"
        [ text "All direct votes on the listed tags will be moved to this tag. WARNING: cannot be undone!", br [] []
        , table [ class "compact" ] <| List.indexedMap (\i p -> tr []
            [ td [ style "text-align" "right" ] [ small [] [ text <| p.id ++ ":" ] ]
            , td [] [ a [ href <| "/" ++ p.id ] [ text p.name ] ]
            , td [] [ inputButton "remove" (MergeDel i) [] ]
            ]
          ) model.merge
        , A.view mergeConfig model.mergeAdd [placeholder "Add tag to merge..."]
        ]
      ]
    ]
  , article [ class "submit" ]
    [ Html.map Editsum (Editsum.view model.editsum)
    , submitButton "Submit" model.state (isValid model)
    ]
  ]
