module Lib.Autocomplete exposing
  ( Config
  , SearchSource(..)
  , SourceConfig
  , Model
  , Msg
  , boardSource
  , tagSource
  , traitSource
  , vnSource
  , producerSource
  , staffSource
  , charSource
  , animeSource
  , resolutionSource
  , engineSource
  , init
  , clear
  , refocus
  , update
  , view
  )

import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (..)
import Html.Keyed as Keyed
import Json.Encode as JE
import Json.Decode as JD
import Task
import Process
import Browser.Dom as Dom
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Api as Api
import Gen.Types exposing (boardTypes)
import Gen.Api as GApi
import Gen.Boards as GB
import Gen.Tags as GT
import Gen.Traits as GTR
import Gen.VN as GV
import Gen.Producers as GP
import Gen.Staff as GS
import Gen.Chars as GC
import Gen.Anime as GA
import Gen.Resolutions as GR
import Gen.Engines as GE


type alias Config m a =
    -- How to wrap a Msg from this model into a Msg of the using model
  { wrap     : Msg a -> m
    -- A unique 'id' of the input box (necessary for the blur/focus events)
  , id       : String
    -- The source defines where to get autocomplete results from and how to display them
  , source   : SourceConfig m a
  }


type SearchSource m a
    -- API endpoint to query for completion results + Function to decode results from the API
  = Endpoint (String -> (GApi.Response -> m) -> Cmd m) (GApi.Response -> Maybe (List a))
    -- API endpoint that returns the full list of possible results + Function to decode results from the API + Function to match results against a query
  | LazyList ((GApi.Response -> m) -> Cmd m) (GApi.Response -> Maybe (List a)) (String -> List a -> List a)
    -- Pure function for instant completion results
  | Func (String -> List a)


type alias SourceConfig m a =
    -- Where to get completion results from
  { source   : SearchSource m a
    -- How to display the decoded results
  , view     : a -> List (Html m)
    -- Unique ID of an item (must not be an empty string).
    -- This is used to remember selection across data refreshes and to optimize
    -- HTML generation.
  , key      : a -> String
  }


boardSource : SourceConfig m GApi.ApiBoardResult
boardSource =
  { source  = Endpoint (\s -> GB.send { search = s })
    <| \x -> case x of
      GApi.BoardResult e -> Just e
      _ -> Nothing
  , view    = (\i ->
    [ text <| Maybe.withDefault "" (lookup i.btype boardTypes)
    ] ++ case i.title of
      Just title -> [ b [ class "grayedout" ] [ text " > " ], text title ]
      _ -> []
    )
  , key     = \i -> i.btype ++ String.fromInt i.iid
  }


tagtraitStatus i =
  case (i.searchable, i.applicable, i.state) of
    (_,     _,     0) -> b [ class "grayedout" ] [ text " (awaiting approval)" ]
    (_,     _,     1) -> b [ class "grayedout" ] [ text " (deleted)" ] -- (not returned by the API for now)
    (False, False, _) -> b [ class "grayedout" ] [ text " (meta)" ]
    (True,  False, _) -> b [ class "grayedout" ] [ text " (not applicable)" ]
    (False, True,  _) -> b [ class "grayedout" ] [ text " (not searchable)" ]
    _ -> text ""


tagSource : SourceConfig m GApi.ApiTagResult
tagSource =
  { source  = Endpoint (\s -> GT.send { search = s })
    <| \x -> case x of
      GApi.TagResult e -> Just e
      _ -> Nothing
  , view    = \i -> [ text i.name, tagtraitStatus i ]
  , key     = \i -> String.fromInt i.id
  }


traitSource : SourceConfig m GApi.ApiTraitResult
traitSource =
  { source  = Endpoint (\s -> GTR.send { search = s })
    <| \x -> case x of
      GApi.TraitResult e -> Just e
      _ -> Nothing
  , view    = \i ->
    [ case i.group_name of
        Nothing -> text ""
        Just g -> b [ class "grayedout" ] [ text <| g ++ " / " ]
    , text i.name
    , tagtraitStatus i
    ]
  , key     = \i -> String.fromInt i.id
  }


vnSource : SourceConfig m GApi.ApiVNResult
vnSource =
  { source  = Endpoint (\s -> GV.send { search = [s], hidden = False })
    <| \x -> case x of
      GApi.VNResult e -> Just e
      _ -> Nothing
  , view    = \i ->
    [ b [ class "grayedout" ] [ text <| "v" ++ String.fromInt i.id ++ ": " ]
    , text i.title ]
  , key     = \i -> String.fromInt i.id
  }


producerSource : SourceConfig m GApi.ApiProducerResult
producerSource =
  { source  = Endpoint (\s -> GP.send { search = [s], hidden = False })
    <| \x -> case x of
      GApi.ProducerResult e -> Just e
      _ -> Nothing
  , view    = \i ->
    [ b [ class "grayedout" ] [ text <| "p" ++ String.fromInt i.id ++ ": " ]
    , text i.name ]
  , key     = \i -> String.fromInt i.id
  }


staffSource : SourceConfig m GApi.ApiStaffResult
staffSource =
  { source  = Endpoint (\s -> GS.send { search = s })
    <| \x -> case x of
      GApi.StaffResult e -> Just e
      _ -> Nothing
  , view    = \i ->
    [ b [ class "grayedout" ] [ text <| "s" ++ String.fromInt i.id ++ ": " ]
    , text i.name ]
  , key     = \i -> String.fromInt i.aid
  }


charSource : SourceConfig m GApi.ApiCharResult
charSource =
  { source  = Endpoint (\s -> GC.send { search = s })
    <| \x -> case x of
      GApi.CharResult e -> Just e
      _ -> Nothing
  , view    = \i ->
    [ b [ class "grayedout" ] [ text <| "c" ++ String.fromInt i.id ++ ": " ]
    , text i.name
    , Maybe.withDefault (text "") <| Maybe.map (\m ->
        b [ class "grayedout" ] [ text <| " (instance of c" ++ String.fromInt m.id ++ ": " ++ m.name ]
      ) i.main
    ]
  , key     = \i -> String.fromInt i.id
  }


animeSource : SourceConfig m GApi.ApiAnimeResult
animeSource =
  { source  = Endpoint (\s -> GA.send { search = s })
    <| \x -> case x of
      GApi.AnimeResult e -> Just e
      _ -> Nothing
  , view    = \i ->
    [ b [ class "grayedout" ] [ text <| "a" ++ String.fromInt i.id ++ ": " ]
    , text i.title ]
  , key     = \i -> String.fromInt i.id
  }


resolutionSource : SourceConfig m GApi.ApiResolutions
resolutionSource =
  { source  = LazyList
                (GR.send {})
                (\x -> case x of
                        GApi.Resolutions e -> Just e
                        _ -> Nothing)
                (\s l -> List.filter (\v -> String.contains (String.toLower s) (String.toLower v.resolution)) l |> List.take 10)
  , view    = \i -> [ text i.resolution, b [ class "grayedout" ] [ text <| " (" ++ String.fromInt i.count ++ ")" ] ]
  , key     = \i -> i.resolution
  }


engineSource : SourceConfig m GApi.ApiEngines
engineSource =
  { source  = LazyList
                (GE.send {})
                (\x -> case x of
                        GApi.Engines e -> Just e
                        _ -> Nothing)
                (\s l -> List.filter (\v -> String.contains (String.toLower s) (String.toLower v.engine)) l |> List.take 10)
  , view    = \i -> [ text i.engine, b [ class "grayedout" ] [ text <| " (" ++ String.fromInt i.count ++ ")" ] ]
  , key     = \i -> i.engine
  }


type alias Model a =
  { visible  : Bool
  , value    : String
  , results  : List a
  , all      : Maybe (List a) -- Used by LazyList
  , sel      : String
  , default  : String
  , loading  : Bool
  , wait     : Int
  }


init : String -> Model a
init s =
  { visible  = False
  , value    = s
  , results  = []
  , all      = Nothing
  , sel      = ""
  , default  = s
  , loading  = False
  , wait     = 0
  }


clear : Model a -> String -> Model a
clear m v = { m
  | value    = v
  , results  = []
  , sel      = ""
  , default  = v
  , loading  = False
  }


type Msg a
  = Noop
  | Focus
  | Blur
  | Input String
  | Search Int
  | Key String
  | Sel String
  | Enter a
  | Results String GApi.Response


select : Config m a -> Int -> Model a -> Model a
select cfg offset model =
  let
    get n   = List.drop n model.results |> List.head
    count   = List.length model.results
    find (n,i) = if cfg.source.key i == model.sel then Just n else Nothing
    curidx  = List.indexedMap (\a b -> (a,b)) model.results |> List.filterMap find |> List.head
    nextidx = (Maybe.withDefault -1 curidx) + offset
    nextsel = if nextidx < 0 then 0 else if nextidx >= count then count-1 else nextidx
  in
    { model | sel = Maybe.withDefault "" <| Maybe.map cfg.source.key <| get nextsel }


-- Blur and focus the input on enter.
refocus : Config m a -> Cmd m
refocus cfg = Dom.blur cfg.id
       |> Task.andThen (always (Dom.focus cfg.id))
       |> Task.attempt (always (cfg.wrap Noop))


update : Config m a -> Msg a -> Model a -> (Model a, Cmd m, Maybe a)
update cfg msg model =
  let
    mod m = (m, Cmd.none, Nothing)
  in
  case msg of
    Noop    -> mod model
    Blur    -> mod { model | visible = False }
    Focus   -> mod { model | loading = False, visible = True }
    Sel s   -> mod { model | sel = s }
    Enter r -> (model, refocus cfg, Just r)

    Key "Enter"     -> (model, refocus cfg,
      case List.filter (\i -> cfg.source.key i == model.sel) model.results |> List.head of
        Just x -> Just x
        Nothing -> List.head model.results)
    Key "ArrowUp"   -> mod <| select cfg -1 model
    Key "ArrowDown" -> mod <| select cfg  1 model
    Key _           -> mod model

    Input s ->
      let m = { model | value = s, default = "" }
      in
      if String.trim s == ""
      then mod { m | loading = False, results = [] }
      else case (cfg.source.source) of
        Endpoint _ _ ->
          ( { m | loading = True,  wait = model.wait + 1 }
          , Task.perform (always <| cfg.wrap <| Search <| model.wait + 1) (Process.sleep 500)
          , Nothing )
        LazyList e _ f ->
          case (model.loading, model.all) of
            (_, Just l) -> mod { m | results = f s l }
            (True, _) -> mod m
            (False, _) -> ({ m | loading = True }, e (cfg.wrap << Results ""), Nothing)
        Func f -> mod { m | results = f s }

    Search i ->
      if model.value == "" || model.wait /= i
      then mod model
      else case cfg.source.source of
        Endpoint e _ -> (model, e model.value (cfg.wrap << Results model.value), Nothing)
        LazyList _ _ _ -> mod model
        Func _ -> mod model

    Results s r -> mod <|
      case cfg.source.source of
        Endpoint _ d -> if s /= model.value then model else { model | loading = False, results = d r |> Maybe.withDefault [] }
        LazyList _ d f -> let all = d r in { model | loading = False, all = all, results = Maybe.map (\l -> f model.value l) all |> Maybe.withDefault [] }
        Func _ -> model


view : Config m a -> Model a -> List (Attribute m) -> Html m
view cfg model attrs =
  let
    input =
      inputText cfg.id model.value (cfg.wrap << Input) <|
        [ autocomplete False
        , onFocus <| cfg.wrap Focus
        , onBlur  <| cfg.wrap Blur
        , style "width" "270px"
        , custom "keydown" <| JD.map (\c ->
                 if c == "Enter" || c == "ArrowUp" || c == "ArrowDown"
                 then { preventDefault = True,  stopPropagation = True,  message = cfg.wrap (Key c) }
                 else { preventDefault = False, stopPropagation = False, message = cfg.wrap (Key c) }
            ) <| JD.field "key" JD.string
        ] ++ attrs

    visible = model.visible && model.value /= model.default && not (model.loading && List.isEmpty model.results)

    msg = [("",
        if List.isEmpty model.results
        then li [ class "msg" ] [ text "No results" ]
        else text ""
      )]

    item i =
      ( cfg.source.key i
      , li []
        [ a
          [ href "#"
          , classList [("active", cfg.source.key i == model.sel)]
          , onMouseOver <| cfg.wrap <| Sel <| cfg.source.key i
          , onMouseDown <| cfg.wrap <| Enter i
          ] <| cfg.source.view i
        ]
      )

  in div [ class "elm_dd", class "search", style "width" "300px" ]
    [ div [ classList [("hidden", not visible)] ] [ div [] [ Keyed.node "ul" [] <| msg ++ List.map item model.results ] ]
    , Html.form [] [ input ]
    , span [ class "spinner", classList [("hidden", not model.loading)] ] []
    ]
