port module ImageFlagging exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Array
import Dict
import Browser
import Browser.Events as EV
import Browser.Dom as DOM
import Task
import Process
import Json.Decode as JD
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Lib.Api as Api
import Lib.Ffi as Ffi
import Gen.Api as GApi
import Gen.Images as GI
import Gen.ImageVote as GIV


main : Program GI.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \m -> Sub.batch <| EV.onResize Resize :: if m.warn || m.myVotes < 100 then [] else [ EV.onKeyDown (keydown m), EV.onKeyUp (keyup m) ]
  }


port preload : String -> Cmd msg


type alias Model =
  { warn      : Bool
  , single    : Bool
  , fullscreen: Bool
  , showVotes : Bool
  , myVotes   : Int
  , nsfwToken : String
  , mod       : Bool
  , exclVoted : Bool
  , images    : Array.Array GApi.ApiImageResult
  , index     : Int
  , desc      : (Maybe Int, Maybe Int)
  , changes   : Dict.Dict String GIV.SendVotes
  , saved     : Bool
  , saveTimer : Bool
  , saveState : Api.State
  , loadState : Api.State
  , loadDone  : Bool -- If we have received the last batch of images
  , pWidth    : Int
  , pHeight   : Int
  }

init : GI.Recv -> Model
init d =
  { warn      = d.warn
  , single    = d.single
  , fullscreen= False
  , showVotes = d.single
  , myVotes   = d.my_votes
  , nsfwToken = d.nsfw_token
  , mod       = d.mod
  , exclVoted = True
  , images    = Array.fromList d.images
  , index     = if d.single then 0 else List.length d.images
  , desc      = Maybe.withDefault (Nothing,Nothing) <| Maybe.map (\i -> (i.my_sexual, i.my_violence)) <| if d.single then List.head d.images else Nothing
  , changes   = Dict.empty
  , saved     = False
  , saveTimer = False
  , saveState = Api.Normal
  , loadState = Api.Normal
  , loadDone  = False
  , pWidth    = d.pWidth
  , pHeight   = d.pHeight
  }


keyToVote : Model -> String -> Maybe (Maybe Int, Maybe Int, Bool)
keyToVote model k =
  let (s,v,o) = Maybe.withDefault (Nothing,Nothing,False) <| Maybe.map (\i -> (i.my_sexual, i.my_violence, i.my_overrule)) <| Array.get model.index model.images
  in case k of
      "1" -> Just (Just 0, Just 0, o)
      "2" -> Just (Just 1, Just 0, o)
      "3" -> Just (Just 2, Just 0, o)
      "4" -> Just (Just 0, Just 1, o)
      "5" -> Just (Just 1, Just 1, o)
      "6" -> Just (Just 2, Just 1, o)
      "7" -> Just (Just 0, Just 2, o)
      "8" -> Just (Just 1, Just 2, o)
      "9" -> Just (Just 2, Just 2, o)
      "s" -> Just (Just 0, v, o)
      "d" -> Just (Just 1, v, o)
      "f" -> Just (Just 2, v, o)
      "j" -> Just (s, Just 0, o)
      "k" -> Just (s, Just 1, o)
      "l" -> Just (s, Just 2, o)
      _   -> Nothing

keydown : Model -> JD.Decoder Msg
keydown model = JD.andThen (\k -> keyToVote model k |> Maybe.map (\(s,v,_) -> JD.succeed (Desc s v)) |> Maybe.withDefault (JD.fail "")) (JD.field "key" JD.string)

keyup : Model -> JD.Decoder Msg
keyup model =
  JD.andThen (\k ->
    case k of
      "ArrowLeft"  -> JD.succeed Prev
      "ArrowRight" -> JD.succeed Next
      "v"          -> JD.succeed (Fullscreen (not model.fullscreen))
      "Escape"     -> JD.succeed (Fullscreen False)
      _            -> keyToVote model k |> Maybe.map (\(s,v,o) -> JD.succeed (Vote s v o True)) |> Maybe.withDefault (JD.fail "")
  ) (JD.field "key" JD.string)


type Msg
  = SkipWarn
  | ExclVoted Bool
  | ShowVotes
  | Fullscreen Bool
  | Desc (Maybe Int) (Maybe Int)
  | Load GApi.Response
  | Vote (Maybe Int) (Maybe Int) Bool Bool
  | Save
  | Saved GApi.Response
  | Prev
  | Next
  | Focus String
  | Resize Int Int


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  let -- Load more images if we're about to run out
      load (m,c) =
        if not m.loadDone && not m.single && m.loadState /= Api.Loading && Array.length m.images - m.index <= 3
        then ({ m | loadState = Api.Loading }, Cmd.batch [ c, GI.send { excl_voted = m.exclVoted } Load ])
        else (m,c)
      -- Start a timer to save changes
      save (m,c) =
        if not m.saveTimer && not (Dict.isEmpty m.changes) && m.saveState /= Api.Loading
        then ({ m | saveTimer = True }, Cmd.batch [ c, Task.perform (always Save) (Process.sleep (if m.single then 500 else 5000)) ])
        else (m,c)
      -- Set desc and showVotes to current image
      desc (m,c) =
        let v = Maybe.withDefault (Nothing,Nothing) <| Maybe.map (\i -> (i.my_sexual, i.my_violence)) <| Array.get m.index m.images
        in ({ m | desc = v, showVotes = m.single || (Tuple.first v /= Nothing && Tuple.second v /= Nothing)}, c)
      -- Preload next image
      pre (m, c) =
        case Array.get (m.index+1) m.images of
          Just i  -> (m, Cmd.batch [ c, preload (imageUrl i.id) ])
          Nothing -> (m, c)
  in
  case msg of
    SkipWarn -> load ({ model | warn = False }, Cmd.none)
    ExclVoted b -> ({ model | exclVoted = b }, Cmd.none)
    ShowVotes -> ({ model | showVotes = not model.showVotes }, Cmd.none)
    Fullscreen b -> ({ model | fullscreen = b }, Cmd.none)
    Desc s v -> ({ model | desc = (s,v) }, Cmd.none)

    Load (GApi.ImageResult l) ->
      let nm = { model | loadState = Api.Normal, loadDone = List.length l < 30, images = Array.append model.images (Array.fromList l) }
          nc = if nm.index < 1000 then nm
               else { nm | index = nm.index - 100, images = Array.slice 100 (Array.length nm.images) nm.images }
      in pre (nc, Cmd.none)
    Load e -> ({ model | loadState = Api.Error e }, Cmd.none)

    Vote s v o _ ->
      case Array.get model.index model.images of
        Nothing -> (model, Cmd.none)
        Just i ->
          let m = { model | saved = False, images = Array.set model.index { i | my_sexual = s, my_violence = v, my_overrule = o } model.images }
              adv = if not m.single && (not model.exclVoted || i.my_sexual == Nothing || i.my_violence == Nothing) then 1 else 0
          in case (i.token,s,v) of
              -- Complete vote, mark it as a change and go to next image
              (Just token, Just xs, Just xv) -> desc <| pre <| save <| load
                ({ m | index     = m.index + adv
                     , myVotes   = m.myVotes + adv
                     , changes   = Dict.insert i.id { id = i.id, token = token, sexual = xs, violence = xv, overrule = o } m.changes
                 }, Cmd.none)
              -- Otherwise just save it internally
              _ -> (m, Cmd.none)

    Save -> ({ model | saveTimer = False, saveState = Api.Loading, changes = Dict.empty }, GIV.send { votes = Dict.values model.changes } Saved)
    Saved r -> save ({ model | saved = True, saveState = if r == GApi.Success then Api.Normal else Api.Error r }, Cmd.none)

    Prev -> desc ({ model | saved = False, index = model.index - (if model.index == 0 then 0 else 1) }, Cmd.none)
    Next -> desc <| pre <| load ({ model | saved = False, index = model.index + (if model.single then 0 else 1) }, Cmd.none)

    -- Unfocus a vote radio button when it is focussed in order to prevent arrow keys from changing selection.
    Focus s -> (model, Task.attempt (always SkipWarn) (DOM.blur s))

    Resize width height -> ({ model | pWidth = width, pHeight = height }, Cmd.none)



view : Model -> Html Msg
view model =
  let
    boxwidth = clamp 600 1200 <| model.pWidth - 300
    boxheight = clamp 300 700 <| model.pHeight - clamp 200 350 (model.pHeight - 500)
    px n = String.fromInt n ++ "px"
    stat avg stddev =
      case (avg, stddev) of
        (Just a, Just s) -> Ffi.fmtFloat a 2 ++ " σ " ++ Ffi.fmtFloat s 2
        _ -> "-"

    but i s v lid lbl =
      let sel = i.my_sexual == s && i.my_violence == v
      in li [ classList [("sel", sel || (s /= i.my_sexual && Tuple.first model.desc == s) || (v /= i.my_violence && Tuple.second model.desc == v))] ]
         [ label [ onMouseOver (Desc s v), onMouseOut (Desc i.my_sexual i.my_violence) ]
           [ input [ type_ "radio", onCheck (Vote s v i.my_overrule), checked sel, onFocus (Focus lid), id lid ] [], text lbl ]
         ]

    votestats i =
      let num = String.fromInt i.votecount ++ (if i.votecount == 1 then " vote" else " votes")
      in div [] <|
      if List.isEmpty i.votes
      then [ p [ class "center" ] [ text "No other votes on this image yet." ] ]
      else if not model.showVotes
      then [ p [ class "center" ] [ text num, text ", ", a [ href "#", onClickD ShowVotes ] [ text "show »" ] ] ]
      else
      [ p [ class "center" ]
        [ text num
        , small [] [ text " / " ], text <| "sexual: "   ++ stat i.sexual_avg i.sexual_stddev
        , small [] [ text " / " ], text <| "violence: " ++ stat i.violence_avg i.violence_stddev
        ]
      , table [] <|
        List.map (\v ->
          tr [ classList [("ignored", v.ignore)]]
          [ td [ Ffi.innerHtml v.user ] []
          , td [] [ text <| if v.sexual   == 0 then "Safe" else if v.sexual   == 1 then "Suggestive" else "Explicit" ]
          , td [] [ text <| if v.violence == 0 then "Tame" else if v.violence == 1 then "Violent"    else "Brutal" ]
          , td [] <| Maybe.withDefault [] <| Maybe.map (\u -> [ a [ href <| "/img/list?view=" ++ model.nsfwToken ++ "&u=" ++ u ] [ text "votes" ] ]) v.uid
          ]
        ) i.votes
      ]

    imgView i =
      [ div []
        [ inputButton "««" Prev [ classList [("invisible", model.index == 0)] ]
        , span [] <|
          case i.entry of
            Nothing -> []
            Just e ->
              [ small [] [ text (e.id ++ ":") ]
              , a [ href ("/" ++ e.id) ] [ text e.title ]
              ]
        , inputButton "»»" Next [ classList [("invisible", model.single)] ]
        ]
      , div [ style "width" (px (boxwidth + 10)), style "height" (px boxheight) ] <|
        -- Don't use an <img> here, changing the src= causes the old image to be displayed with the wrong dimensions while the new image is being loaded.
        [ a [ href (imageUrl i.id), style "background-image" ("url("++imageUrl i.id++")")
            , style "background-size" (if i.width > boxwidth || i.height > boxheight then "contain" else "auto")
            ] [ text "" ] ]
      , div []
        [ span [] <|
          case model.saveState of
            Api.Error e -> [ b [ class "standout" ] [ text <| "Save failed: " ++ Api.showResponse e ] ]
            _ ->
              [ span [ class "spinner", classList [("invisible", model.saveState == Api.Normal)] ] []
              , small [] [ text <|
                if not (Dict.isEmpty model.changes)
                then "Unsaved votes: " ++ String.fromInt (Dict.size model.changes)
                else if model.saved then "Saved!" else "" ]
              ]
        , span []
          [ a [ href <| "/img/" ++ i.id ] [ text i.id ]
          , small [] [ text " / " ]
          , a [ href (imageUrl i.id) ] [ text <| String.fromInt i.width ++ "x" ++ String.fromInt i.height ]
          ]
        ]
      , div [] <| if i.token == Nothing then [] else
        [ p [] <|
          case Tuple.first model.desc of
            Just 0 -> [ b [] [ text "Safe" ], br [] []
                      , text "- No nudity", br [] []
                      , text "- No (implied) sexual actions", br [] []
                      , text "- No suggestive clothing or visible underwear", br [] []
                      , text "- No sex toys" ]
            Just 1 -> [ b [] [ text "Suggestive" ], br [] []
                      , text "- Visible underwear or skimpy clothing", br [] []
                      , text "- Erotic posing", br [] []
                      , text "- Sex toys (but not visibly being used)", br [] []
                      , text "- No visible genitals or female nipples" ]
            Just 2 -> [ b [] [ text "Explicit" ], br [] []
                      , text "- Visible genitals or female nipples", br [] []
                      , text "- Penetrative sex (regardless of clothing)", br [] []
                      , text "- Visible use of sex toys" ]
            _ -> []
        , ul []
          [ li [] [ b [] [ text "Sexual" ] ]
          , but i (Just 0) i.my_violence "vio0" " Safe"
          , but i (Just 1) i.my_violence "vio1" " Suggestive"
          , but i (Just 2) i.my_violence "vio2" " Explicit"
          , if model.mod then li [ class "overrule" ] [ label [ title "Overrule" ] [ inputCheck "" i.my_overrule (\b -> Vote i.my_sexual i.my_violence b True), text " Overrule" ] ] else text ""
          ]
        , ul []
          [ li [] [ b [] [ text "Violence" ] ]
          , but i i.my_sexual (Just 0) "sex0" " Tame"
          , but i i.my_sexual (Just 1) "sex1" " Violent"
          , but i i.my_sexual (Just 2) "sex2" " Brutal"
          ]
        , p [] <|
          case Tuple.second model.desc of
            Just 0 -> [ b [] [ text "Tame" ], br [] []
                      , text "- No visible violence", br [] []
                      , text "- Tame slapstick comedy", br [] []
                      , text "- Weapons, but not used to harm anyone", br [] []
                      , text "- Only very minor visible blood or bruises", br [] [] ]
            Just 1 -> [ b [] [ text "Violent" ], br [] []
                      , text "- Visible blood", br [] []
                      , text "- Non-comedic fight scenes", br [] []
                      , text "- Physically harmful activities" ]
            Just 2 -> [ b [] [ text "Brutal" ], br [] []
                      , text "- Excessive amounts of blood", br [] []
                      , text "- Cut off limbs", br [] []
                      , text "- Sliced-open bodies", br [] []
                      , text "- Harmful activities leading to death" ]
            _ -> []
        ]
      , p [ class "center" ] <| if i.token == Nothing then [] else
        [ text "Not sure? Read the ", a [ href "/d19" ] [ text "full guidelines" ], text " for more detailed guidance."
        , if model.myVotes < 100 then text "" else
          span [] [ text " (", a [ href <| Ffi.urlStatic ++ "/f/imgvote-keybindings.svg" ] [ text "keyboard shortcuts" ], text ")" ]
        ]
      , votestats i
      , if model.fullscreen -- really lazy fullscreen mode
        then div [ class "fullscreen", style "background-image" ("url("++imageUrl i.id++")"), onClick (Fullscreen False) ] [ text "" ]
        else text ""
      ]

  in div [ class "mainbox" ]
  [ h1 [] [ text "Image flagging" ]
  , div [ class "imageflag", style "width" (px (boxwidth + 10)) ] <|
    if model.warn
    then [ ul []
           [ li [] [ text "Make sure you are familiar with the ", a [ href "/d19" ] [ text "image flagging guidelines" ], text "." ]
           , li [] [ b [ class "standout" ] [ text "WARNING: " ], text "Images shown may include spoilers, be highly offensive and/or contain very explicit depictions of sexual acts." ]
           ]
         , br [] []
         , if model.single
           then text ""
           else label [] [ inputCheck "" (not model.exclVoted) (\b -> ExclVoted (not b)), text " Include images I already voted on.", br [] [] ]
         , inputButton "Continue" SkipWarn []
         ]
    else case (Array.get model.index model.images, model.loadState) of
           (Just i, _)    -> imgView i
           (_, Api.Loading) -> [ span [ class "spinner" ] [] ]
           (_, Api.Error e) -> [ b [ class "standout" ] [ text <| Api.showResponse e ] ]
           (_, Api.Normal)  -> [ text "No more images to vote on!" ]
  ]
