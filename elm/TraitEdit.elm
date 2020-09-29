module TraitEdit exposing (main)

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
import Gen.TraitEdit as GTE


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
  , alias        : String
  , state        : Int
  , sexual       : Bool
  , description  : TP.Model
  , searchable   : Bool
  , applicable   : Bool
  , defaultspoil : Int
  , parents      : List GTE.RecvParents
  , parentAdd    : A.Model GApi.ApiTraitResult
  , order        : Int
  , addedby      : String
  , canMod       : Bool
  , dupNames     : List GApi.ApiDupNames
  }


init : GTE.Recv -> Model
init d =
  { formstate    = Api.Normal
  , id           = d.id
  , name         = d.name
  , alias        = d.alias
  , state        = d.state
  , sexual       = d.sexual
  , description  = TP.bbcode d.description
  , searchable   = d.searchable
  , applicable   = d.applicable
  , defaultspoil = d.defaultspoil
  , parents      = d.parents
  , parentAdd    = A.init ""
  , order        = d.order
  , addedby      = d.addedby
  , canMod       = d.can_mod
  , dupNames     = []
  }


splitAliases : String -> List String
splitAliases l = String.lines l |> List.map String.trim |> List.filter (\s -> s /= "")

findDup : Model -> String -> List GApi.ApiDupNames
findDup model a = List.filter (\t -> String.toLower t.name == String.toLower a) model.dupNames

isValid : Model -> Bool
isValid model = not (List.any (findDup model >> List.isEmpty >> not) (model.name :: splitAliases model.alias))

parentConfig : A.Config Msg GApi.ApiTraitResult
parentConfig = { wrap = ParentSearch, id = "parentadd", source = A.traitSource }


encode : Model -> GTE.Send
encode m =
  { id           = m.id
  , name         = m.name
  , alias        = m.alias
  , state        = m.state
  , sexual       = m.sexual
  , description  = m.description.data
  , searchable   = m.searchable
  , applicable   = m.applicable
  , defaultspoil = m.defaultspoil
  , parents      = List.map (\l -> {id=l.id}) m.parents
  , order        = m.order
  }


type Msg
  = Name String
  | Alias String
  | State Int
  | Searchable Bool
  | Applicable Bool
  | Sexual Bool
  | DefaultSpoil Int
  | Description TP.Msg
  | ParentDel Int
  | ParentSearch (A.Msg GApi.ApiTraitResult)
  | Order String
  | Submit
  | Submitted (GApi.Response)


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Name s        -> ({ model | name = s }, Cmd.none)
    Alias s       -> ({ model | alias = String.replace "," "\n" s }, Cmd.none)
    State n       -> ({ model | state = n }, Cmd.none)
    Searchable b  -> ({ model | searchable = b }, Cmd.none)
    Applicable b  -> ({ model | applicable = b }, Cmd.none)
    Sexual b      -> ({ model | sexual = b }, Cmd.none)
    DefaultSpoil n-> ({ model | defaultspoil = n }, Cmd.none)
    Order s       -> ({ model | order = Maybe.withDefault 0 (String.toInt s) }, Cmd.none)
    Description m -> let (nm,nc) = TP.update m model.description in ({ model | description = nm }, Cmd.map Description nc)

    ParentDel i   -> ({ model | parents = delidx i model.parents }, Cmd.none)
    ParentSearch m ->
      let (nm, c, res) = A.update parentConfig m model.parentAdd
      in case res of
        Nothing -> ({ model | parentAdd = nm }, c)
        Just p  ->
          if List.any (\e -> e.id == p.id) model.parents
          then ({ model | parentAdd = nm }, c)
          else ({ model | parentAdd = A.clear nm "", parents = model.parents ++ [{ id = p.id, name = p.name, group = p.group_name }] }, c)

    Submit -> ({ model | formstate = Api.Loading }, GTE.send (encode model) Submitted)
    Submitted (GApi.DupNames l) -> ({ model | dupNames = l, formstate = Api.Normal }, Cmd.none)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | formstate = Api.Error r }, Cmd.none)


view : Model -> Html Msg
view model =
  form_ Submit (model.formstate == Api.Loading)
  [ div [ class "mainbox" ]
    [ h1 [] [ text <| if model.id == Nothing then "Submit new trait" else "Edit trait" ]
    , table [ class "formtable" ]
      [ if model.id == Nothing then text "" else
        formField "Added by" [ span [ Ffi.innerHtml model.addedby ] [], br_ 2 ]
      , formField "name::Primary name" [ inputText "name" model.name Name GTE.valName ]
      , formField "alias::Aliases"
        -- BUG: Textarea doesn't validate the maxlength and patterns for aliases, we don't have a client-side fallback check either.
        [ inputTextArea "alias" model.alias Alias []
        , let dups = List.concatMap (findDup model) (model.name :: splitAliases model.alias)
          in if List.isEmpty dups
             then span [] [ br [] [], text "Trait name and aliases must be self-describing and unique within the same group." ]
             else div []
             [ b [ class "standout" ] [ text "The following trait names are already present in the same group:" ]
             , ul [] <| List.map (\t ->
                 li [] [ a [ href ("/i"++String.fromInt t.id) ] [ text t.name ] ]
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
        formField "" [ label [] [ inputCheck "" model.searchable Searchable, text " Searchable (people can use this trait to find characters)" ] ]
      , if not model.canMod then text "" else
        formField "" [ label [] [ inputCheck "" model.applicable Applicable, text " Applicable (people can apply this trait to characters)" ] ]
      , formField "" [ label [] [ inputCheck "" model.sexual Sexual, text " Indicates sexual content" ] ]
      , formField "defaultspoil::Default spoiler level" [ inputSelect "defaultspoil" model.defaultspoil DefaultSpoil GTE.valDefaultspoil 
        [ (0, "No spoiler")
        , (1, "Minor spoiler")
        , (2, "Major spoiler")
        ] ]
      , text "" -- aliases
      , formField "description::Description"
        [ TP.view "description" model.description Description 700 ([rows 12, cols 50] ++ GTE.valDescription) []
        , text "What should the trait be used for? Having a good description helps users choose which traits to assign to characters."
        ]
      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "" ] ]
      , formField "Parent traits"
        [ table [ class "compact" ] <| List.indexedMap (\i p -> tr []
            [ td [ style "text-align" "right" ] [ b [ class "grayedout" ] [ text <| "i" ++ String.fromInt p.id ++ ":" ] ]
            , td []
              [ Maybe.withDefault (text "") <| Maybe.map (\g -> b [ class "grayedout" ] [ text (g ++ " / ") ]) p.group
              , a [ href <| "/i" ++ String.fromInt p.id ] [ text p.name ]
              ]
            , td [] [ inputButton "remove" (ParentDel i) [] ]
            ]
          ) model.parents
        , A.view parentConfig model.parentAdd [placeholder "Add parent trait..."]
        ]
      , if not (List.isEmpty model.parents) then text "" else
        formField "order::Group order"
        [ inputText "order" (String.fromInt model.order) Order (style "width" "50px" :: GTE.valOrder)
        , text " Only meaningful if this trait is as a \"group\", i.e. a trait without any parents."
        , text " This number determines the order in which the groups are displayed on character pages."
        ]
      ]
    ]
  , div [ class "mainbox" ]
    [ fieldset [ class "submit" ] [ submitButton "Submit" model.formstate (isValid model) ] ]
  ]
