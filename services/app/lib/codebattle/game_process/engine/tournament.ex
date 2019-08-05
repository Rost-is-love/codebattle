defmodule Codebattle.GameProcess.Engine.Tournament do
  import Codebattle.GameProcess.Engine.Base

  alias Codebattle.GameProcess.FsmHelpers
  alias Codebattle.Bot.PlaybookAsyncRunner

  @game_timeout 60 * 3

  alias Codebattle.GameProcess.{
    Play,
    Server,
    GlobalSupervisor,
    Fsm,
    Player,
    FsmHelpers,
    ActiveGames,
    Notifier
  }

  alias Codebattle.{Repo, Game}
  alias Codebattle.Bot.RecorderServer

  def create_game(players) do
    level = "elementary"
    task = get_task(level, players)

    game =
      Repo.insert!(%Game{state: "playing", level: level, type: "tournament", task_id: task.id})

    fsm =
      Fsm.new()
      |> Fsm.create_tournament_game(%{
        players: Enum.map(players, fn x -> Codebattle.GameProcess.Player.build(x) end),
        game_id: game.id,
        level: level,
        type: "tournament",
        starts_at: TimeHelper.utc_now(),
        timeout_seconds: @game_timeout,
        task: task,
        joins_at: TimeHelper.utc_now()
      })

    ActiveGames.create_game(game.id, fsm)
    {:ok, _} = GlobalSupervisor.start_game(game.id, fsm)

    Enum.map(players, fn player ->
      if player.is_bot do
        PlaybookAsyncRunner.create_server(%{game_id: game.id, bot: player})

        PlaybookAsyncRunner.run!(%{
          game_id: game.id,
          task_id: task.id,
          bot_id: player.id,
          opponent_data: 100_000
        })
      end
    end)

    {:ok, fsm}
  end

  # real users
  def get_task(level, [%{is_bot: false}, %{is_bot: false}] = players) do
    get_random_task(level, Enum.map(players, fn x -> x.id end))
  end

  # bot and user

  def get_task(level, players) do
    {:ok, task} = Codebattle.GameProcess.Engine.Bot.get_task(level)
    task
  end
end