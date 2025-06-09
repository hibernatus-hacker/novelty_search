defmodule NoveltySearch.Behaviors do
  @moduledoc """
  Behavior characterization and distance metric implementations for different domains.
  """

  alias Nx

  @doc """
  Calculate Euclidean distance between two behavior vectors.
  """
  def euclidean_distance(behavior1, behavior2) do
    b1 = to_tensor(behavior1)
    b2 = to_tensor(behavior2)
    
    Nx.subtract(b1, b2) |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()
  end

  @doc """
  Calculate Manhattan distance between two behavior vectors.
  """
  def manhattan_distance(behavior1, behavior2) do
    b1 = to_tensor(behavior1)
    b2 = to_tensor(behavior2)
    
    Nx.subtract(b1, b2) |> Nx.abs() |> Nx.sum() |> Nx.to_number()
  end

  @doc """
  Calculate cosine similarity between two behavior vectors.
  Returns a distance metric (1 - cosine_similarity).
  """
  def cosine_distance(behavior1, behavior2) do
    b1 = to_tensor(behavior1)
    b2 = to_tensor(behavior2)
    
    dot_product = Nx.dot(b1, b2) |> Nx.to_number()
    norm1 = Nx.pow(b1, 2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()
    norm2 = Nx.pow(b2, 2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()
    
    if norm1 == 0.0 or norm2 == 0.0 do
      1.0
    else
      cosine_sim = dot_product / (norm1 * norm2)
      1.0 - cosine_sim
    end
  end

  @doc """
  Behavior characterization for 2D navigation tasks.
  Returns [x, y] position.
  """
  def navigation_2d_behavior(final_position) do
    case final_position do
      {x, y} -> [x, y]
      [x, y] -> [x, y]
      _ -> raise ArgumentError, "Invalid position format"
    end
  end

  @doc """
  Behavior characterization for trajectory-based tasks.
  Samples points along the trajectory for a fixed-size representation.
  """
  def trajectory_behavior(trajectory, num_samples \\ 10) do
    total_points = length(trajectory)
    
    if total_points <= num_samples do
      # Pad with last position if trajectory is too short
      last_pos = List.last(trajectory) || {0, 0}
      padding = List.duplicate(last_pos, num_samples - total_points)
      
      (trajectory ++ padding)
      |> Enum.flat_map(fn {x, y} -> [x, y] end)
    else
      # Sample evenly spaced points
      indices = 
        0..(num_samples - 1)
        |> Enum.map(fn i -> 
          round(i * (total_points - 1) / (num_samples - 1))
        end)
      
      indices
      |> Enum.map(fn idx -> Enum.at(trajectory, idx) end)
      |> Enum.flat_map(fn {x, y} -> [x, y] end)
    end
  end

  @doc """
  Behavior characterization for robotic tasks with multiple objectives.
  Combines multiple behavioral features with normalization.
  """
  def multi_objective_behavior(features) when is_map(features) do
    # Example features: %{distance_traveled: 10.5, energy_used: 23.1, items_collected: 3}
    
    # Define normalization ranges for each feature
    normalizations = %{
      distance_traveled: {0, 100},
      energy_used: {0, 50},
      items_collected: {0, 10},
      final_x: {-50, 50},
      final_y: {-50, 50}
    }
    
    features
    |> Enum.sort_by(fn {k, _v} -> k end)  # Ensure consistent ordering
    |> Enum.map(fn {feature, value} ->
      case Map.get(normalizations, feature) do
        {min_val, max_val} ->
          # Normalize to [0, 1]
          normalized = (value - min_val) / (max_val - min_val)
          max(0, min(1, normalized))  # Clamp to [0, 1]
        nil ->
          value  # Use raw value if no normalization defined
      end
    end)
  end

  @doc """
  Behavior characterization based on grid occupancy.
  Useful for exploration tasks.
  """
  def grid_occupancy_behavior(trajectory, grid_size \\ {10, 10}) do
    {width, height} = grid_size
    
    # Create occupancy grid
    grid = 
      trajectory
      |> Enum.reduce(%{}, fn {x, y}, acc ->
        grid_x = min(max(0, floor(x)), width - 1)
        grid_y = min(max(0, floor(y)), height - 1)
        Map.put(acc, {grid_x, grid_y}, 1)
      end)
    
    # Convert to flat vector
    for y <- 0..(height - 1),
        x <- 0..(width - 1) do
      Map.get(grid, {x, y}, 0)
    end
  end

  @doc """
  Behavior characterization for time-series or sequential tasks.
  Uses statistical features of the sequence.
  """
  def sequence_statistics_behavior(sequence) do
    values = Enum.map(sequence, &elem(&1, 1))  # Assuming sequence of {time, value} pairs
    
    if Enum.empty?(values) do
      [0, 0, 0, 0, 0]  # Default features
    else
      tensor = Nx.tensor(values)
      
      [
        Nx.mean(tensor) |> Nx.to_number(),
        Nx.standard_deviation(tensor) |> Nx.to_number(),
        Nx.reduce_min(tensor) |> Nx.to_number(),
        Nx.reduce_max(tensor) |> Nx.to_number(),
        List.last(values)  # Final value
      ]
    end
  end

  @doc """
  Create a custom behavior characterization function that combines multiple features.
  """
  def create_composite_behavior(extractors) when is_list(extractors) do
    fn data ->
      extractors
      |> Enum.flat_map(fn extractor -> extractor.(data) end)
    end
  end

  # Helper functions

  defp to_tensor(behavior) when is_list(behavior) do
    Nx.tensor(behavior)
  end
  
  defp to_tensor(behavior) when is_struct(behavior, Nx.Tensor) do
    behavior
  end
end