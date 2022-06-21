module Tagmod exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy
import Browser
import Browser.Navigation exposing (reload)
import Browser.Dom exposing (focus)
import Task
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.Ffi as Ffi
import Lib.Autocomplete as A
import Gen.Api as GApi
import Gen.Tagmod as GT


main : Program GT.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }

type alias Tag = GT.RecvTags

type Sel
  = NoSel
  | Vote Int
  | Spoil (Maybe Int)
  | Note
  | NoteSet

type alias Model =
  { state    : Api.State
  , title    : String
  , id       : String
  , mod      : Bool
  , tags     : List Tag
  , saved    : List Tag
  , changed  : Bool
  , selId    : String
  , selType  : Sel
  , negCount : Int
  , negShow  : Bool
  , add      : A.Model GApi.ApiTagResult
  , addMsg   : String
  }


init : GT.Recv -> Model
init f =
  { state    = Api.Normal
  , title    = f.title
  , id       = f.id
  , mod      = f.mod
  , tags     = f.tags
  , saved    = f.tags
  , changed  = False
  , selId    = ""
  , selType  = NoSel
  , negCount = List.length <| List.filter (\t -> t.rating <= 0) f.tags
  , negShow  = False
  , add      = A.init ""
  , addMsg   = ""
  }

searchConfig : A.Config Msg GApi.ApiTagResult
searchConfig = { wrap = TagSearch, id = "tagadd", source = A.tagSource }


type Msg
  = Noop
  | SetSel String Sel
  | SetVote String Int
  | SetOver String Bool
  | SetSpoil String (Maybe Int)
  | SetNote String String
  | NegShow Bool
  | TagSearch (A.Msg GApi.ApiTagResult)
  | Submit
  | Submitted GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  let
    changed m = { m | changed = m.saved /= m.tags }
    modtag id f = changed { model | addMsg = "", tags = List.map (\t -> if t.id == id then f t else t) model.tags }
  in
  case msg of
    Noop -> (model, Cmd.none)
    SetSel id v ->
      ( if model.selType == NoteSet && not (id == model.selId && v == NoSel) then model else { model | selId = id, selType = v }
      , if v == NoteSet then Task.attempt (always Noop) (focus "tag_note") else Cmd.none)

    SetVote  id v -> (modtag id (\t -> { t | vote = v }), Cmd.none)
    SetOver  id b -> (modtag id (\t -> { t | overrule = b }), Cmd.none)
    SetSpoil id s -> (modtag id (\t -> { t | spoil = s }), Cmd.none)
    SetNote  id s -> (modtag id (\t -> { t | notes = s }), Cmd.none)
    NegShow  b    -> ({ model | negShow = b }, Cmd.none)

    TagSearch m ->
      let (nm, c, res) = A.update searchConfig m model.add
      in case res of
        Nothing -> ({ model | add = nm }, c)
        Just t ->
          let (nl, ms) =
                if t.hidden && t.locked                            then ([], "Can't add deleted tags")
                else if not t.applicable                           then ([], "Tag is not applicable")
                else if List.any (\it -> it.id == t.id) model.tags then ([], "Tag is already in the list")
                else ([{ id = t.id, vote = 0, spoil = Nothing, overrule = False, notes = "", cat = "new", name = t.name
                       , rating = 0, count = 0, spoiler = 0, overruled = False, othnotes = "", hidden = t.hidden, locked = t.locked, applicable = t.applicable }], "")
          in (changed { model | add = if ms == "" then A.clear nm "" else nm, tags = model.tags ++ nl, addMsg = ms }, c)

    Submit ->
      ( { model | state = Api.Loading, addMsg = "" }
      , GT.send { id = model.id, tags = List.map (\t -> { id = t.id, vote = t.vote, spoil = t.spoil, overrule = t.overrule, notes = t.notes }) model.tags } Submitted)
    Submitted GApi.Success -> (model, reload)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)



viewTag : Tag -> Sel -> String -> Bool -> Html Msg
viewTag t sel vid mod =
  let
    -- Similar to VNWeb::Tags::Lib::tagscore_
    tagscore s =
      div [ class "tagscore", classList [("negative", s < 0)] ]
      [ span [] [ text <| Ffi.fmtFloat s 1 ]
      , div [ style "width" <| String.fromFloat (abs (s/3*30)) ++ "px" ] []
      ]

    vote  = case sel of Vote v  -> v
                        _       -> t.vote
    spoil = case sel of Spoil s -> s
                        _       -> t.spoil
  in
    tr [] <|
    [ td [ class "tc_tagname" ]
      [ a [ href <| "/"++t.id, style "text-decoration" (if t.applicable && not (t.hidden && t.locked) then "none" else "line-through") ] [ text t.name ]
      , case (t.hidden, t.locked, t.applicable) of
          (True, False, _) -> b [ class "grayedout" ] [ text " (awaiting approval)" ]
          (True, True,  _) -> b [ class "grayedout" ] [ text " (deleted)" ]
          (_, _, False)    -> b [ class "grayedout" ] [ text " (not applicable)" ]
          _ -> text ""
      ]
    , td [ class "tc_myvote buts"  ]
      [ a [ href "#", onMouseOver (SetSel t.id (Vote -3)), onMouseOut (SetSel "" NoSel), onClickD (SetVote t.id -3), classList [("ld", vote <  0)], title "Downvote"    ] []
      , a [ href "#", onMouseOver (SetSel t.id (Vote  0)), onMouseOut (SetSel "" NoSel), onClickD (SetVote t.id  0), classList [("l0", vote == 0)], title "Remove vote" ] []
      , a [ href "#", onMouseOver (SetSel t.id (Vote  1)), onMouseOut (SetSel "" NoSel), onClickD (SetVote t.id  1), classList [("l1", vote >= 1)], title "+1"          ] []
      , a [ href "#", onMouseOver (SetSel t.id (Vote  2)), onMouseOut (SetSel "" NoSel), onClickD (SetVote t.id  2), classList [("l2", vote >= 2)], title "+2"          ] []
      , a [ href "#", onMouseOver (SetSel t.id (Vote  3)), onMouseOut (SetSel "" NoSel), onClickD (SetVote t.id  3), classList [("l3", vote == 3)], title "+3"          ] []
      ]
    , td [ class "tc_myover" ] [ if mod && t.vote /= 0 then inputCheck "" t.overrule (SetOver t.id) else text "" ]
    , td [ class "tc_myspoil buts" ] <|
      if t.vote <= 0 then [] else
      [ a [ href "#", onMouseOver (SetSel t.id (Spoil (Just 3))), onMouseOut (SetSel "" NoSel), onClickD (SetSpoil t.id (Just 3)), classList [("s3", spoil == Just 3 )], title "False"         ] []
      , a [ href "#", onMouseOver (SetSel t.id (Spoil Nothing)),  onMouseOut (SetSel "" NoSel), onClickD (SetSpoil t.id Nothing),  classList [("sn", spoil == Nothing)], title "Unknown"       ] []
      , a [ href "#", onMouseOver (SetSel t.id (Spoil (Just 0))), onMouseOut (SetSel "" NoSel), onClickD (SetSpoil t.id (Just 0)), classList [("s0", spoil == Just 0 )], title "Not a spoiler" ] []
      , a [ href "#", onMouseOver (SetSel t.id (Spoil (Just 1))), onMouseOut (SetSel "" NoSel), onClickD (SetSpoil t.id (Just 1)), classList [("s1", spoil == Just 1 )], title "Minor spoiler" ] []
      , a [ href "#", onMouseOver (SetSel t.id (Spoil (Just 2))), onMouseOut (SetSel "" NoSel), onClickD (SetSpoil t.id (Just 2)), classList [("s2", spoil == Just 2 )], title "Major spoiler" ] []
      ]
    , td [ class "tc_mynote" ] <|
      if t.vote == 0 then [] else
      [ span
        [ onMouseOver (SetSel t.id Note)
        , onMouseOut (SetSel "" NoSel)
        , onClickD (SetSel t.id NoteSet)
        , style "opacity" <| if t.notes == "" then "0.5" else "1.0"
        ] [ text "💬" ]
      ]
    ] ++
    case sel of
      Vote 0         -> [ td [ colspan 3 ] [ text "Remove vote" ] ]
      Vote 1         -> [ td [ colspan 3 ] [ text "Vote +1" ] ]
      Vote 2         -> [ td [ colspan 3 ] [ text "Vote +2" ] ]
      Vote 3         -> [ td [ colspan 3 ] [ text "Vote +3" ] ]
      Vote _         -> [ td [ colspan 3 ] [ text "Downvote (-3)" ] ]
      Spoil (Just 3) -> [ td [ colspan 3 ] [ text "This eventually turns out to be false" ] ]
      Spoil Nothing  -> [ td [ colspan 3 ] [ text "Spoiler status not known" ] ]
      Spoil (Just 0) -> [ td [ colspan 3 ] [ text "This is not a spoiler" ] ]
      Spoil (Just 1) -> [ td [ colspan 3 ] [ text "This is a minor spoiler" ] ]
      Spoil (Just 2) -> [ td [ colspan 3 ] [ text "This is a major spoiler" ] ]
      Note           -> [ td [ colspan 3 ] [ if t.notes == "" then text "Set note" else div [ class "noteview" ] [ text t.notes ] ] ]
      NoteSet ->
        [ td [ colspan 3, class "compact" ]
          [ Html.form [ onSubmit (SetSel t.id NoSel) ]
            [ inputText "tag_note" t.notes (SetNote t.id) (onBlur (SetSel t.id NoSel) :: style "width" "400px" :: style "position" "absolute" :: placeholder "Set note..." :: GT.valTagsNotes) ]
          ]
        ]
      _ ->
        if t.count == 0 then [ td [ colspan 3 ] [] ]
        else
        [ td [ class "tc_allvote" ]
          [ tagscore t.rating
          , i [ classList [("grayedout", t.overruled)] ] [ text <| " (" ++ String.fromInt t.count ++ ")" ]
          , if not t.overruled then text ""
            else b [ class "standout", style "font-weight" "bold", title "Tag overruled. All votes other than that of the moderator who overruled it will be ignored." ] [ text "!" ]
          ]
        , td [ class "tc_allspoil"] [ text <| if t.spoiler < 0 then "False" else Ffi.fmtFloat t.spoiler 2 ]
        , td [ class "tc_allwho"  ]
          [ span [ style "opacity" <| if t.othnotes == "" then "0" else "1", style "cursor" "default", title t.othnotes ] [ text "💬 " ]
          , a [ href <| "/g/links?v="++vid++"&t="++t.id ] [ text "Who?" ]
          ]
        ]

viewHead : Bool -> Int -> Bool -> Html Msg
viewHead mod negCount negShow =
  thead []
  [ tr []
    [ td [ style "font-weight" "normal", style "text-align" "right" ] <|
      if negCount == 0 then []
      else [ linkRadio negShow NegShow [ text "Show downvoted tags " ], i [] [ text <| " (" ++ String.fromInt negCount ++ ")" ] ]
    , td [ colspan 4, class "tc_you" ] [ text "You" ]
    , td [ colspan 3, class "tc_others" ] [ text "Others" ]
    ]
  , tr []
    [ td [ class "tc_tagname" ] [ text "Tag" ]
    , td [ class "tc_myvote"  ] [ text "Rating" ]
    , td [ class "tc_myover"  ] [ text (if mod then "O" else "") ]
    , td [ class "tc_myspoil" ] [ text "Spoiler" ]
    , td [ class "tc_mynote"  ] []
    , td [ class "tc_allvote" ] [ text "Rating" ]
    , td [ class "tc_allspoil"] [ text "Spoiler" ]
    , td [ class "tc_allwho"  ] []
    ]
  ]

viewFoot : Api.State -> Bool -> A.Model GApi.ApiTagResult -> String -> Html Msg
viewFoot state changed add addMsg =
  tfoot [] [ tr [] [ td [ colspan 8 ]
  [ div [ style "display" "flex", style "justify-content" "space-between" ]
    [ A.view searchConfig add [placeholder "Add tags..."]
    , if addMsg /= ""
      then b [ class "standout" ] [ text addMsg ]
      else if changed
      then b [ class "standout" ] [ text "You have unsaved changes" ]
      else text ""
    , submitButton "Save changes" state True
    ]
  , text "Check the ", a [ href "/g" ] [ text "tag list" ], text " to browse all available tags."
  , br [] []
  , text "Can't find what you're looking for? ", a [ href "/g/new" ] [ text "Request a new tag" ]
  ] ] ]


-- The table has a lot of interactivity, the use of Html.Lazy is absolutely necessary for good responsiveness.
view : Model -> Html Msg
view model =
  form_ "" Submit (model.state == Api.Loading)
    [ div [ class "mainbox" ]
      [ h1 [] [ text <| "Edit tags for " ++ model.title ]
      , p []
        [ text "This is where you can add tags to the visual novel and vote on the existing tags."
        , br [] []
        , text "Don't forget to also select the appropriate spoiler option for each tag."
        , br [] []
        , text "For more information, check out the ", a [ href "/d10" ] [ text "guidelines." ]
        ]
      , table [ class "tgl stripe" ]
        [ Html.Lazy.lazy3 viewHead model.mod model.negCount model.negShow
        , Html.Lazy.lazy4 viewFoot model.state model.changed model.add model.addMsg
        , tbody []
          <| List.concatMap (\(id,nam) ->
            let lst = List.filter (\t -> t.cat == id && (t.cat == "new" || t.rating > 0 || t.vote > 0 || model.negShow)) model.tags
            in
              if List.length lst == 0
              then []
              else tr [class "tagmod_cat"] [ td [] [text nam], td [ class "tc_you", colspan 4 ] [], td [ class "tc_others", colspan 3 ] [] ]
                   :: List.map (\t -> Html.Lazy.lazy4 viewTag t (if t.id == model.selId then model.selType else NoSel) model.id model.mod) lst)
          [ ("cont", "Content")
          , ("ero",  "Sexual content")
          , ("tech", "Technical")
          , ("new",  "Newly added tags")
          ]
        ]
      ]
    ]
