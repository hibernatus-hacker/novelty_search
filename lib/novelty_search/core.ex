defmodule NoveltySearch.Core do
  @moduledoc """
  Core novelty search implementation with archive management.
  Based on the novelty search algorithm for evolutionary robotics.
  """

  alias Nx

  defstruct [:archive, :k_nearest, :archive_threshold, :min_dist_to_archive, :behavior_characterization]

  @doc """
  Initialize a new novelty search instance.
  
  Options:
    - k_nearest: number of nearest neighbors to consider (default: 15)
    - archive_threshold: minimum novelty to add to archive (default: 6.0)
    - min_dist_to_archive: minimum distance to existing archive members (default: 3.0)
    - behavior_characterization: function to extract behavior from evaluation result
  """
  def new(opts \\ []) do
    %__MODULE__{
      archive: Keyword.get(opts, :archive, []),
      k_nearest: Keyword.get(opts, :k_nearest, 15),
      archive_threshold: Keyword.get(opts, :archive_threshold, 6.0),
      min_dist_to_archive: Keyword.get(opts, :min_dist_to_archive, 3.0),
      behavior_characterization: Keyword.get(opts, :behavior_characterization, & &1)
    }
  end

  @doc """
  Calculate novelty score for a behavior compared to current population and archive.
  """
  def novelty_score(%__MODULE__{} = ns, behavior, population_behaviors) do
    all_behaviors = ns.archive ++ population_behaviors
    
    if Enum.empty?(all_behaviors) do
      0.0
    else
      behavior_tensor = behavior_to_tensor(behavior)
      
      distances = 
        all_behaviors
        |> Enum.map(&behavior_to_tensor/1)
        |> Enum.map(fn other -> 
          Nx.subtract(behavior_tensor, other) |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()
        end)
        |> Enum.sort()
      
      # Take k nearest neighbors (or all if less than k)
      k = min(ns.k_nearest, length(distances))
      nearest_distances = Enum.take(distances, k)
      
      # Average distance to k nearest neighbors
      if k > 0 do
        Enum.sum(nearest_distances) / k
      else
        0.0
      end
    end
  end

  @doc """
  Update the novelty archive with new behaviors if they meet criteria.
  """
  def update_archive(%__MODULE__{} = ns, new_behaviors, novelty_scores) do
    candidates = 
      Enum.zip(new_behaviors, novelty_scores)
      |> Enum.filter(fn {_behavior, score} -> score > ns.archive_threshold end)
      |> Enum.sort_by(fn {_behavior, score} -> -score end)
    
    new_archive = 
      Enum.reduce(candidates, ns.archive, fn {behavior, _score}, acc ->
        if should_add_to_archive?(ns, behavior, acc) do
          [behavior | acc]
        else
          acc
        end
      end)
    
    %{ns | archive: new_archive}
  end

  @doc """
  Evaluate a population using novelty search.
  Returns {novelty_scores, updated_novelty_search}.
  """
  def evaluate_population(%__MODULE__{} = ns, population, eval_fn) do
    # Evaluate all individuals in parallel using Task.async_stream
    eval_results = 
      population
      |> Task.async_stream(eval_fn, max_concurrency: System.schedulers_online(), timeout: 30_000)
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Extract behaviors using the characterization function (also parallel)
    behaviors = 
      eval_results
      |> Task.async_stream(ns.behavior_characterization, max_concurrency: System.schedulers_online())
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Calculate novelty scores (parallel computation)
    novelty_scores = 
      behaviors
      |> Task.async_stream(fn behavior ->
        novelty_score(ns, behavior, behaviors)
      end, max_concurrency: System.schedulers_online())
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Update archive
    updated_ns = update_archive(ns, behaviors, novelty_scores)
    
    {novelty_scores, updated_ns}
  end

  # Private functions

  defp behavior_to_tensor(behavior) when is_list(behavior) do
    Nx.tensor(behavior)
  end
  
  defp behavior_to_tensor(behavior) when is_struct(behavior, Nx.Tensor) do
    behavior
  end

  defp should_add_to_archive?(%__MODULE__{} = ns, behavior, archive) do
    behavior_tensor = behavior_to_tensor(behavior)
    
    Enum.all?(archive, fn archive_member ->
      distance = 
        archive_member
        |> behavior_to_tensor()
        |> then(&(Nx.subtract(behavior_tensor, &1) |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt()))
        |> Nx.to_number()
      
      distance >= ns.min_dist_to_archive
    end)
  end

  @doc """
  Get archive statistics.
  """
  def archive_stats(%__MODULE__{} = ns) do
    %{
      size: length(ns.archive),
      archive: ns.archive
    }
  end

  @doc """
  Clear the archive.
  """
  def clear_archive(%__MODULE__{} = ns) do
    %{ns | archive: []}
  end
end