defmodule NoveltySearch.Serialization do
  @moduledoc """
  Serialization support for saving and loading novelty search experiments and archives.
  Provides functionality to persist experiment state, novelty archives, and analysis data.
  """

  @doc """
  Save a novelty search archive to a JSON file.
  """
  def save_archive(archive, filename) when is_list(archive) do
    data = %{
      archive: archive,
      size: length(archive),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write(filename, json)
      {:error, reason} ->
        {:error, "Failed to encode archive: #{inspect(reason)}"}
    end
  end

  @doc """
  Load a novelty search archive from a JSON file.
  """
  def load_archive(filename) do
    case File.read(filename) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            {:ok, data["archive"]}
          {:error, reason} ->
            {:error, "Failed to decode archive: #{inspect(reason)}"}
        end
      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  @doc """
  Save experiment results including final archive, best individuals, and metadata.
  """
  def save_experiment_results(results, filename) do
    experiment_data = %{
      final_archive: results.final_archive,
      archive_size: length(results.final_archive),
      best_individuals: results.best_individuals,
      generations: results.generations,
      max_novelty_scores: results.max_novelty_scores,
      archive_size_history: results.archive_size_history,
      parameters: results.parameters,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      elixir_version: System.version(),
      experiment_duration: results.duration
    }
    
    case Jason.encode(experiment_data, pretty: true) do
      {:ok, json} ->
        File.write(filename, json)
      {:error, reason} ->
        {:error, "Failed to encode experiment results: #{inspect(reason)}"}
    end
  end

  @doc """
  Load experiment results from a JSON file.
  """
  def load_experiment_results(filename) do
    case File.read(filename) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, reason} ->
            {:error, "Failed to decode experiment results: #{inspect(reason)}"}
        end
      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  @doc """
  Save population with their behaviors and novelty scores for analysis.
  """
  def save_population_snapshot(population, behaviors, novelty_scores, generation, filename) do
    population_data = %{
      generation: generation,
      population_size: length(population),
      individuals: Enum.zip([population, behaviors, novelty_scores])
        |> Enum.with_index()
        |> Enum.map(fn {{individual, behavior, novelty}, index} ->
          %{
            id: index,
            individual: serialize_individual(individual),
            behavior: behavior,
            novelty_score: novelty
          }
        end),
      statistics: %{
        mean_novelty: Enum.sum(novelty_scores) / length(novelty_scores),
        max_novelty: Enum.max(novelty_scores),
        min_novelty: Enum.min(novelty_scores),
        novelty_std: calculate_std(novelty_scores)
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    case Jason.encode(population_data, pretty: true) do
      {:ok, json} ->
        File.write(filename, json)
      {:error, reason} ->
        {:error, "Failed to encode population snapshot: #{inspect(reason)}"}
    end
  end

  @doc """
  Save behavioral diversity analysis to CSV format for easy analysis.
  """
  def save_behavioral_analysis_csv(archive, filename) do
    header = "behavior_x,behavior_y,archive_index\n"
    
    rows = 
      archive
      |> Enum.with_index()
      |> Enum.map(fn {behavior, index} ->
        case behavior do
          [x, y] -> "#{x},#{y},#{index}"
          [x, y | _] -> "#{x},#{y},#{index}"  # Handle behaviors with more than 2 dimensions
          _ -> "#{inspect(behavior)},#{index}"  # Fallback for other formats
        end
      end)
      |> Enum.join("\n")
    
    content = header <> rows <> "\n"
    File.write(filename, content)
  end

  @doc """
  Create a comprehensive experiment report in markdown format.
  """
  def generate_experiment_report(results, filename) do
    report = """
    # Novelty Search Experiment Report

    **Generated:** #{DateTime.utc_now() |> DateTime.to_iso8601()}
    **Duration:** #{results[:duration] || "Unknown"}
    **Elixir Version:** #{System.version()}

    ## Experiment Parameters

    - **Generations:** #{results[:generations] || "Unknown"}
    - **Population Size:** #{get_in(results, [:parameters, :population_size]) || "Unknown"}
    - **K-Nearest Neighbors:** #{get_in(results, [:parameters, :k_nearest]) || "Unknown"}
    - **Archive Threshold:** #{get_in(results, [:parameters, :archive_threshold]) || "Unknown"}
    - **Mutation Rate:** #{get_in(results, [:parameters, :mutation_rate]) || "Unknown"}

    ## Results Summary

    - **Final Archive Size:** #{length(results[:final_archive] || [])}
    - **Best Novelty Score:** #{if results[:max_novelty_scores], do: Enum.max(results[:max_novelty_scores]), else: "Unknown"}
    - **Average Archive Growth:** #{if results[:archive_size_history], do: length(results[:final_archive] || []) / length(results[:archive_size_history]), else: "Unknown"} behaviors per generation

    ## Archive Size History

    #{format_history(results[:archive_size_history])}

    ## Max Novelty Score History

    #{format_history(results[:max_novelty_scores])}

    ## Archive Behaviors

    The final archive contains #{length(results[:final_archive] || [])} unique behaviors:

    #{format_behaviors(results[:final_archive])}

    ---
    *Report generated by NoveltySearch.Serialization*
    """
    
    File.write(filename, report)
  end

  # Private helper functions

  defp serialize_individual(individual) do
    case individual do
      %{weights1: _, bias1: _, weights2: _, bias2: _} ->
        # Neural network individual - convert Nx tensors to lists
        %{
          weights1: Nx.to_list(individual.weights1),
          bias1: Nx.to_list(individual.bias1),
          weights2: Nx.to_list(individual.weights2),
          bias2: Nx.to_list(individual.bias2)
        }
      _ ->
        # Generic individual
        individual
    end
  end

  defp calculate_std(values) when is_list(values) and length(values) > 1 do
    mean = Enum.sum(values) / length(values)
    variance = Enum.sum(Enum.map(values, fn x -> (x - mean) * (x - mean) end)) / length(values)
    :math.sqrt(variance)
  end
  defp calculate_std(_), do: 0.0

  defp format_history(nil), do: "No history available"
  defp format_history(history) when is_list(history) do
    history
    |> Enum.with_index(1)
    |> Enum.map(fn {value, gen} -> "Generation #{gen}: #{value}" end)
    |> Enum.join("\n")
  end

  defp format_behaviors(nil), do: "No behaviors available"
  defp format_behaviors(behaviors) when is_list(behaviors) do
    behaviors
    |> Enum.take(20)  # Show first 20 behaviors
    |> Enum.with_index(1)
    |> Enum.map(fn {behavior, index} -> "#{index}. #{inspect(behavior)}" end)
    |> Enum.join("\n")
    |> then(fn formatted ->
      if length(behaviors) > 20 do
        formatted <> "\n... and #{length(behaviors) - 20} more behaviors"
      else
        formatted
      end
    end)
  end
end