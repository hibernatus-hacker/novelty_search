defmodule NoveltySearch.NEATIntegration do
  @moduledoc """
  Integration module for using novelty search with NEAT or other evolutionary algorithms.
  This provides a simple interface to replace fitness-based selection with novelty-based selection.
  """

  alias NoveltySearch.Core
  alias NoveltySearch.Maze

  @doc """
  Run novelty search with a custom evolutionary algorithm.
  
  The evolution_fn should accept:
    - population: current population
    - scores: novelty scores for each individual
    - generation: current generation number
  
  And return:
    - {new_population, stats} where stats is a map of statistics
  
  The evaluate_fn should accept an individual and return evaluation results.
  """
  def run(opts) do
    # Extract options
    generations = Keyword.fetch!(opts, :generations)
    population_size = Keyword.fetch!(opts, :population_size)
    init_population_fn = Keyword.fetch!(opts, :init_population_fn)
    evolution_fn = Keyword.fetch!(opts, :evolution_fn)
    evaluate_fn = Keyword.fetch!(opts, :evaluate_fn)
    behavior_fn = Keyword.get(opts, :behavior_fn, & &1)
    
    # Initialize novelty search
    novelty_search = Core.new(
      k_nearest: Keyword.get(opts, :k_nearest, 15),
      archive_threshold: Keyword.get(opts, :archive_threshold, 6.0),
      behavior_characterization: behavior_fn
    )
    
    # Initialize population
    initial_population = init_population_fn.(population_size)
    
    # Track experiment timing
    start_time = System.system_time(:millisecond)
    
    # Run evolution
    {final_population, final_novelty_search, history} = 
      Enum.reduce(1..generations, {initial_population, novelty_search, []}, fn gen, {pop, ns, hist} ->
        # Evaluate population with novelty search
        {novelty_scores, updated_ns} = Core.evaluate_population(ns, pop, evaluate_fn)
        
        # Run evolutionary step with novelty scores instead of fitness
        {new_pop, stats} = evolution_fn.(pop, novelty_scores, gen)
        
        # Collect statistics
        gen_stats = Map.merge(stats, %{
          generation: gen,
          max_novelty: Enum.max(novelty_scores),
          avg_novelty: Enum.sum(novelty_scores) / length(novelty_scores),
          archive_size: length(updated_ns.archive)
        })
        
        IO.puts("Generation #{gen}: Max novelty: #{gen_stats.max_novelty}, Archive size: #{gen_stats.archive_size}")
        
        {new_pop, updated_ns, [gen_stats | hist]}
      end)
    
    # Calculate experiment duration and collect results
    end_time = System.system_time(:millisecond)
    duration_ms = end_time - start_time
    
    results = %{
      final_population: final_population,
      novelty_search: final_novelty_search,
      final_archive: final_novelty_search.archive,
      history: Enum.reverse(history),
      archive: final_novelty_search.archive,
      generations: generations,
      max_novelty_scores: Enum.map(Enum.reverse(history), & &1.max_novelty),
      archive_size_history: Enum.map(Enum.reverse(history), & &1.archive_size),
      parameters: opts,
      duration: "#{duration_ms}ms"
    }
    
    # Optional: Save experiment results
    save_results = Keyword.get(opts, :save_results, false)
    if save_results do
      results_file = Keyword.get(opts, :results_file, "experiment_results.json")
      case NoveltySearch.Serialization.save_experiment_results(results, results_file) do
        :ok -> IO.puts("Experiment results saved to #{results_file}")
        {:error, reason} -> IO.puts("Failed to save results: #{reason}")
      end
      
      # Also save archive and generate report
      archive_file = Keyword.get(opts, :archive_file, "final_archive.json")
      case NoveltySearch.Serialization.save_archive(results.final_archive, archive_file) do
        :ok -> IO.puts("Archive saved to #{archive_file}")
        {:error, reason} -> IO.puts("Failed to save archive: #{reason}")
      end
      
      report_file = Keyword.get(opts, :report_file, "experiment_report.md")
      case NoveltySearch.Serialization.generate_experiment_report(results, report_file) do
        :ok -> IO.puts("Report generated: #{report_file}")
        {:error, reason} -> IO.puts("Failed to generate report: #{reason}")
      end
    end
    
    results
  end

  @doc """
  Run novelty search on a maze navigation task using a simple neural network.
  This is a complete example that doesn't require external NEAT implementation.
  """
  def run_maze_experiment(maze \\ :medium, opts \\ []) do
    # Setup maze
    maze_env = case maze do
      :medium -> Maze.medium_maze()
      :hard -> Maze.hard_maze()
      maze_struct when is_struct(maze_struct) -> maze_struct
    end
    
    # Network parameters
    input_size = 11  # 1 bias + 6 rangefinder sensors + 4 radar sensors
    hidden_size = Keyword.get(opts, :hidden_size, 10)
    output_size = 2  # left and right wheel velocities
    
    # Evolution parameters
    generations = Keyword.get(opts, :generations, 250)
    population_size = Keyword.get(opts, :population_size, 150)
    mutation_rate = Keyword.get(opts, :mutation_rate, 0.3)
    mutation_power = Keyword.get(opts, :mutation_power, 0.5)
    
    run(
      generations: generations,
      population_size: population_size,
      k_nearest: 15,
      archive_threshold: 6.0,
      
      # Initialize random neural networks
      init_population_fn: fn size ->
        Enum.map(1..size, fn _ ->
          %{
            weights1: random_matrix(input_size, hidden_size),
            bias1: random_matrix(1, hidden_size),
            weights2: random_matrix(hidden_size, output_size),
            bias2: random_matrix(1, output_size)
          }
        end)
      end,
      
      # Evaluate individual by running maze simulation
      evaluate_fn: fn individual ->
        network_fn = fn inputs ->
          # Simple 2-layer neural network
          inputs_tensor = Nx.tensor([inputs])
          
          hidden = 
            inputs_tensor
            |> Nx.dot(individual.weights1)
            |> Nx.add(individual.bias1)
            |> Nx.tanh()
          
          outputs = 
            hidden
            |> Nx.dot(individual.weights2)
            |> Nx.add(individual.bias2)
            |> Nx.tanh()
            |> Nx.to_flat_list()
          
          outputs
        end
        
        Maze.simulate(maze_env, network_fn)
      end,
      
      # Extract behavior (final position) from evaluation
      behavior_fn: &Maze.behavior_characterization/1,
      
      # Simple evolution with mutation
      evolution_fn: fn population, scores, _generation ->
        # Tournament selection based on novelty scores
        selected = tournament_selection(population, scores, population_size)
        
        # Mutate selected individuals
        new_population = 
          Enum.map(selected, fn individual ->
            if :rand.uniform() < mutation_rate do
              mutate_network(individual, mutation_power)
            else
              individual
            end
          end)
        
        # Statistics
        stats = %{
          best_score: Enum.max(scores),
          avg_score: Enum.sum(scores) / length(scores)
        }
        
        {new_population, stats}
      end
    )
  end

  # Helper functions for simple neural network evolution

  defp random_matrix(rows, cols) do
    key = Nx.Random.key(42)
    {uniform, _} = Nx.Random.uniform(key, -1.0, 1.0, shape: {rows, cols})
    uniform
  end

  defp mutate_network(network, power) do
    %{
      weights1: add_noise(network.weights1, power),
      bias1: add_noise(network.bias1, power),
      weights2: add_noise(network.weights2, power),
      bias2: add_noise(network.bias2, power)
    }
  end

  defp add_noise(tensor, power) do
    key = Nx.Random.key(42)
    {noise, _} = Nx.Random.normal(key, 0.0, power, shape: Nx.shape(tensor))
    Nx.add(tensor, noise)
  end

  defp tournament_selection(population, scores, num_select, tournament_size \\ 3) do
    pop_with_scores = Enum.zip(population, scores)
    
    Enum.map(1..num_select, fn _ ->
      tournament = 
        Enum.map(1..tournament_size, fn _ ->
          Enum.random(pop_with_scores)
        end)
      
      {winner, _score} = Enum.max_by(tournament, fn {_ind, score} -> score end)
      winner
    end)
  end
end