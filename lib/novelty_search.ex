defmodule NoveltySearch do
  @moduledoc """
  Main entry point for the Novelty Search library.
  
  Novelty Search is an evolutionary algorithm that rewards behavioral novelty
  instead of objective fitness, helping to avoid deceptive local optima.
  
  ## Example Usage
  
      # Run a maze navigation experiment
      result = NoveltySearch.run_maze_experiment(:medium, generations: 100)
      
      # Access the novelty archive
      archive_behaviors = result.archive
      
      # Custom usage with your own evolutionary algorithm
      novelty_search = NoveltySearch.Core.new(k_nearest: 15)
      {scores, updated_ns} = NoveltySearch.Core.evaluate_population(
        novelty_search, 
        population, 
        eval_fn
      )
  """

  alias NoveltySearch.{Core, NEATIntegration, Behaviors}

  @doc """
  Run a maze navigation experiment using novelty search.
  
  Options:
    - maze: :medium, :hard, or a custom Maze struct
    - generations: number of generations (default: 250)
    - population_size: size of population (default: 150)
    - hidden_size: hidden layer size for neural networks (default: 10)
    - mutation_rate: probability of mutation (default: 0.3)
    - mutation_power: strength of mutations (default: 0.5)
  """
  defdelegate run_maze_experiment(maze \\ :medium, opts \\ []), to: NEATIntegration

  @doc """
  Create a new novelty search instance.
  
  Options:
    - k_nearest: number of nearest neighbors (default: 15)
    - archive_threshold: minimum novelty for archive (default: 6.0)
    - min_dist_to_archive: minimum distance to archive members (default: 3.0)
    - behavior_characterization: function to extract behavior
  """
  defdelegate new(opts \\ []), to: Core

  @doc """
  Example: Run a simple maze experiment and visualize results.
  """
  def example_maze_run do
    IO.puts("Running novelty search on medium maze...")
    
    result = run_maze_experiment(:medium, 
      generations: 50, 
      population_size: 100
    )
    
    IO.puts("\nExperiment completed!")
    IO.puts("Final archive size: #{length(result.archive)}")
    IO.puts("Archive behaviors (final positions):")
    
    result.archive
    |> Enum.take(10)
    |> Enum.each(fn [x, y] ->
      IO.puts("  Position: (#{Float.round(x, 2)}, #{Float.round(y, 2)})")
    end)
    
    if length(result.archive) > 10 do
      IO.puts("  ... and #{length(result.archive) - 10} more")
    end
    
    result
  end

  @doc """
  Example: Custom behavior characterization for a different domain.
  """
  def example_custom_behavior do
    # Example: Evolving walking gaits with custom behavior
    
    # Define behavior as combination of distance and gait pattern
    behavior_fn = fn evaluation_result ->
      Behaviors.create_composite_behavior([
        fn res -> [res.distance_traveled] end,
        fn res -> Behaviors.sequence_statistics_behavior(res.joint_angles) end
      ]).(evaluation_result)
    end
    
    novelty_search = Core.new(
      behavior_characterization: behavior_fn,
      k_nearest: 10,
      archive_threshold: 4.0
    )
    
    # Dummy population and evaluation for example
    population = Enum.map(1..20, fn i -> %{id: i, genome: :rand.uniform()} end)
    
    eval_fn = fn _individual ->
      # Simulate evaluation
      %{
        distance_traveled: :rand.uniform() * 10,
        joint_angles: Enum.map(1..10, fn _ -> {:rand.uniform(100), :rand.uniform()} end)
      }
    end
    
    {novelty_scores, updated_ns} = Core.evaluate_population(novelty_search, population, eval_fn)
    
    IO.puts("Novelty scores: #{inspect(Enum.take(novelty_scores, 5))} ...")
    IO.puts("Archive size: #{length(updated_ns.archive)}")
    
    updated_ns
  end

  @doc """
  Analyze novelty search results with comprehensive behavioral diversity metrics.
  
  ## Example
  
      # Run an experiment and analyze results
      results = NoveltySearch.NEATIntegration.run_maze_experiment(maze: :medium, generations: 100)
      analysis = NoveltySearch.analyze_experiment_results(results)
      
      # Generate analysis report
      report = NoveltySearch.Analysis.generate_analysis_report(
        results.final_archive,
        results.archive_history
      )
  """
  def analyze_experiment_results(experiment_results) do
    alias NoveltySearch.Analysis
    
    final_archive = experiment_results[:final_archive] || experiment_results[:archive] || []
    
    # Basic diversity analysis
    diversity_metrics = Analysis.behavioral_diversity_metrics(final_archive)
    
    # Behavioral space coverage
    histogram = Analysis.behavioral_histogram(final_archive, bins: 15)
    
    # Clustering analysis
    clustering = Analysis.clustering_analysis(final_archive, k: 5)
    
    # Temporal analysis if history is available
    temporal_analysis = 
      case experiment_results[:archive_history] do
        nil -> 
          IO.puts("No archive history available for temporal analysis")
          %{}
        history -> 
          Analysis.exploration_analysis(history)
      end
    
    analysis_results = %{
      diversity_metrics: diversity_metrics,
      histogram_analysis: histogram,
      clustering_analysis: clustering,
      temporal_analysis: temporal_analysis,
      summary: %{
        total_behaviors: length(final_archive),
        experiment_duration: experiment_results[:duration] || "Unknown",
        generations: experiment_results[:generations] || "Unknown"
      }
    }
    
    # Print summary
    IO.puts("\n=== Novelty Search Analysis Results ===")
    IO.puts("Total unique behaviors discovered: #{length(final_archive)}")
    IO.puts("Mean behavioral distance: #{Float.round(diversity_metrics.mean_distance, 4)}")
    IO.puts("Behavioral diversity index: #{Float.round(diversity_metrics.diversity_index, 4)}")
    
    if Map.has_key?(clustering, :clusters) do
      IO.puts("Number of behavioral clusters: #{length(clustering.clusters)}")
    end
    
    if Map.has_key?(temporal_analysis, :saturation_analysis) do
      saturation = temporal_analysis.saturation_analysis
      IO.puts("Novelty search saturation: #{if saturation.is_saturated, do: "Yes", else: "No"}")
    end
    
    IO.puts("=====================================\n")
    
    analysis_results
  end
end