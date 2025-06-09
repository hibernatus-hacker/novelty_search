defmodule NoveltySearch.Analysis do
  @moduledoc """
  Analysis tools for novelty search experiments including behavioral diversity metrics,
  histograms, and statistical analysis of exploration patterns.
  """

  alias NoveltySearch.Behaviors

  @doc """
  Calculate behavioral diversity metrics for a population or archive.
  """
  def behavioral_diversity_metrics(behaviors, distance_fn \\ &Behaviors.euclidean_distance/2) do
    if length(behaviors) < 2 do
      %{
        mean_distance: 0.0,
        std_distance: 0.0,
        min_distance: 0.0,
        max_distance: 0.0,
        pairwise_distances: [],
        diversity_index: 0.0
      }
    else
      # Calculate all pairwise distances
      pairwise_distances = calculate_pairwise_distances(behaviors, distance_fn)
      
      mean_dist = Enum.sum(pairwise_distances) / length(pairwise_distances)
      std_dist = calculate_std(pairwise_distances)
      min_dist = Enum.min(pairwise_distances)
      max_dist = Enum.max(pairwise_distances)
      
      # Shannon diversity index adapted for behavioral space
      diversity_index = shannon_diversity_index(behaviors)
      
      %{
        mean_distance: mean_dist,
        std_distance: std_dist,
        min_distance: min_dist,
        max_distance: max_dist,
        pairwise_distances: pairwise_distances,
        diversity_index: diversity_index,
        total_behaviors: length(behaviors)
      }
    end
  end

  @doc """
  Create histogram analysis of behavioral space coverage.
  """
  def behavioral_histogram(behaviors, opts \\ []) do
    bins = Keyword.get(opts, :bins, 20)
    dimensions = Keyword.get(opts, :dimensions, 2)
    
    case dimensions do
      1 -> histogram_1d(behaviors, bins)
      2 -> histogram_2d(behaviors, bins)
      _ -> {:error, "Only 1D and 2D histograms are currently supported"}
    end
  end

  @doc """
  Analyze exploration patterns over time during evolution.
  """
  def exploration_analysis(archive_history, _opts \\ []) do
    generations = length(archive_history)
    
    # Calculate diversity metrics for each generation
    diversity_over_time = 
      archive_history
      |> Enum.with_index(1)
      |> Enum.map(fn {archive, gen} ->
        diversity = behavioral_diversity_metrics(archive)
        Map.put(diversity, :generation, gen)
      end)
    
    # Calculate growth rates
    archive_sizes = Enum.map(archive_history, &length/1)
    growth_rates = calculate_growth_rates(archive_sizes)
    
    # Novelty saturation analysis
    saturation_analysis = analyze_novelty_saturation(diversity_over_time)
    
    %{
      generations: generations,
      diversity_over_time: diversity_over_time,
      archive_sizes: archive_sizes,
      growth_rates: growth_rates,
      saturation_analysis: saturation_analysis,
      final_coverage: calculate_space_coverage(List.last(archive_history) || [])
    }
  end

  @doc """
  Analyze behavioral clustering patterns.
  """
  def clustering_analysis(behaviors, opts \\ []) do
    k = Keyword.get(opts, :k, min(5, length(behaviors)))
    distance_fn = Keyword.get(opts, :distance_fn, &Behaviors.euclidean_distance/2)
    
    if length(behaviors) < k do
      %{error: "Not enough behaviors for clustering analysis (need at least #{k})"}
    else
      clusters = k_means_clustering(behaviors, k, distance_fn)
      
      %{
        clusters: clusters,
        cluster_sizes: Enum.map(clusters, &length/1),
        intra_cluster_distances: Enum.map(clusters, &calculate_intra_cluster_distance(&1, distance_fn)),
        inter_cluster_distances: calculate_inter_cluster_distances(clusters, distance_fn)
      }
    end
  end

  @doc """
  Generate a comprehensive analysis report.
  """
  def generate_analysis_report(archive, history \\ nil, opts \\ []) do
    diversity = behavioral_diversity_metrics(archive)
    histogram = behavioral_histogram(archive, opts)
    clustering = clustering_analysis(archive, opts)
    
    exploration = if history do
      exploration_analysis(history, opts)
    else
      %{note: "No history provided - skipping temporal analysis"}
    end
    
    %{
      summary: %{
        total_behaviors: length(archive),
        behavioral_diversity: diversity,
        space_coverage: calculate_space_coverage(archive)
      },
      histogram_analysis: histogram,
      clustering_analysis: clustering,
      exploration_analysis: exploration,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Private helper functions

  defp calculate_pairwise_distances(behaviors, distance_fn) do
    for {b1, i} <- Enum.with_index(behaviors),
        {b2, j} <- Enum.with_index(behaviors),
        i < j do
      distance_fn.(b1, b2)
    end
  end

  defp calculate_std(values) when is_list(values) and length(values) > 1 do
    mean = Enum.sum(values) / length(values)
    variance = Enum.sum(Enum.map(values, fn x -> (x - mean) * (x - mean) end)) / length(values)
    :math.sqrt(variance)
  end
  defp calculate_std(_), do: 0.0

  defp shannon_diversity_index(behaviors) do
    # Discretize behaviors for diversity calculation
    discretized = Enum.map(behaviors, &discretize_behavior/1)
    frequencies = Enum.frequencies(discretized)
    total = length(behaviors)
    
    frequencies
    |> Enum.map(fn {_behavior, count} ->
      p = count / total
      if p > 0, do: -p * :math.log(p), else: 0
    end)
    |> Enum.sum()
  end

  defp discretize_behavior(behavior) when is_list(behavior) do
    # Round to nearest 0.5 for discretization
    Enum.map(behavior, fn x -> Float.round(x * 2) / 2 end)
  end

  defp histogram_1d(behaviors, bins) do
    values = Enum.map(behaviors, fn
      [x] -> x
      [x | _] -> x  # Take first dimension if multi-dimensional
      x when is_number(x) -> x
    end)
    
    if length(values) == 0 do
      %{error: "No valid 1D values found"}
    else
      min_val = Enum.min(values)
      max_val = Enum.max(values)
      bin_width = (max_val - min_val) / bins
      
      bin_counts = 
        values
        |> Enum.map(fn v -> 
          bin_index = min(bins - 1, trunc((v - min_val) / bin_width))
          max(0, bin_index)
        end)
        |> Enum.frequencies()
        |> Map.to_list()
        |> Enum.sort()
      
      %{
        type: "1D",
        bins: bins,
        bin_width: bin_width,
        range: {min_val, max_val},
        counts: bin_counts
      }
    end
  end

  defp histogram_2d(behaviors, bins) do
    xy_values = Enum.map(behaviors, fn
      [x, y] -> {x, y}
      [x, y | _] -> {x, y}  # Take first two dimensions
      _ -> nil
    end) |> Enum.reject(&is_nil/1)
    
    if length(xy_values) == 0 do
      %{error: "No valid 2D values found"}
    else
      x_values = Enum.map(xy_values, &elem(&1, 0))
      y_values = Enum.map(xy_values, &elem(&1, 1))
      
      x_min = Enum.min(x_values)
      x_max = Enum.max(x_values)
      y_min = Enum.min(y_values)
      y_max = Enum.max(y_values)
      
      x_bin_width = (x_max - x_min) / bins
      y_bin_width = (y_max - y_min) / bins
      
      bin_counts = 
        xy_values
        |> Enum.map(fn {x, y} ->
          x_bin = min(bins - 1, max(0, trunc((x - x_min) / x_bin_width)))
          y_bin = min(bins - 1, max(0, trunc((y - y_min) / y_bin_width)))
          {x_bin, y_bin}
        end)
        |> Enum.frequencies()
      
      %{
        type: "2D",
        bins: bins,
        x_range: {x_min, x_max},
        y_range: {y_min, y_max},
        x_bin_width: x_bin_width,
        y_bin_width: y_bin_width,
        counts: bin_counts
      }
    end
  end

  defp calculate_growth_rates(sizes) when length(sizes) < 2, do: []
  defp calculate_growth_rates(sizes) do
    sizes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [prev, curr] ->
      if prev == 0, do: 0.0, else: (curr - prev) / prev
    end)
  end

  defp analyze_novelty_saturation(diversity_over_time) do
    if length(diversity_over_time) < 5 do
      %{error: "Not enough generations for saturation analysis"}
    else
      # Look at the last 10 generations to check for saturation
      recent_diversities = 
        diversity_over_time
        |> Enum.take(-10)
        |> Enum.map(& &1.mean_distance)
      
      trend_slope = calculate_trend_slope(recent_diversities)
      
      %{
        is_saturated: abs(trend_slope) < 0.01,  # Very small slope indicates saturation
        trend_slope: trend_slope,
        recent_diversity_variance: calculate_std(recent_diversities)
      }
    end
  end

  defp calculate_trend_slope(values) when length(values) < 2, do: 0.0
  defp calculate_trend_slope(values) do
    n = length(values)
    x_values = Enum.to_list(1..n)
    
    sum_x = Enum.sum(x_values)
    sum_y = Enum.sum(values)
    sum_xy = Enum.zip(x_values, values) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
    sum_x2 = Enum.map(x_values, fn x -> x * x end) |> Enum.sum()
    
    # Linear regression slope
    (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
  end

  defp calculate_space_coverage(behaviors) do
    case behaviors do
      [] -> %{coverage: 0.0}
      [behavior | _] ->
        dimensions = length(behavior)
        
        if dimensions >= 2 do
          # Calculate convex hull area for 2D coverage
          xy_points = Enum.map(behaviors, fn [x, y | _] -> {x, y} end)
          area = convex_hull_area(xy_points)
          
          %{
            dimensions: dimensions,
            convex_hull_area: area,
            behavior_count: length(behaviors)
          }
        else
          # 1D coverage - just range
          values = Enum.map(behaviors, &hd/1)
          range = Enum.max(values) - Enum.min(values)
          
          %{
            dimensions: 1,
            range: range,
            behavior_count: length(behaviors)
          }
        end
    end
  end

  defp convex_hull_area(points) when length(points) < 3, do: 0.0
  defp convex_hull_area(points) do
    # Simplified convex hull using bounding box for now
    # A full convex hull implementation would be more complex
    x_coords = Enum.map(points, &elem(&1, 0))
    y_coords = Enum.map(points, &elem(&1, 1))
    
    width = Enum.max(x_coords) - Enum.min(x_coords)
    height = Enum.max(y_coords) - Enum.min(y_coords)
    
    width * height
  end

  defp k_means_clustering(behaviors, k, distance_fn) do
    # Simplified k-means implementation
    # Initialize centroids randomly
    centroids = Enum.take_random(behaviors, k)
    
    # Run k-means for a fixed number of iterations
    Enum.reduce(1..10, {behaviors, centroids}, fn _iter, {points, current_centroids} ->
      # Assign points to clusters
      clusters = assign_to_clusters(points, current_centroids, distance_fn)
      
      # Update centroids
      new_centroids = Enum.map(clusters, &calculate_centroid/1)
      
      {points, new_centroids}
    end)
    |> elem(0)
    |> assign_to_clusters(centroids, distance_fn)
  end

  defp assign_to_clusters(points, centroids, distance_fn) do
    clustered_points = 
      Enum.map(points, fn point ->
        closest_centroid_index = 
          centroids
          |> Enum.with_index()
          |> Enum.min_by(fn {centroid, _} -> distance_fn.(point, centroid) end)
          |> elem(1)
        
        {closest_centroid_index, point}
      end)
    
    # Group by cluster index
    clustered_points
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.values()
  end

  defp calculate_centroid(cluster) when length(cluster) == 0, do: []
  defp calculate_centroid(cluster) do
    dimensions = length(hd(cluster))
    
    Enum.map(0..(dimensions - 1), fn dim ->
      values = Enum.map(cluster, &Enum.at(&1, dim))
      Enum.sum(values) / length(values)
    end)
  end

  defp calculate_intra_cluster_distance(cluster, distance_fn) do
    if length(cluster) < 2 do
      0.0
    else
      distances = calculate_pairwise_distances(cluster, distance_fn)
      Enum.sum(distances) / length(distances)
    end
  end

  defp calculate_inter_cluster_distances(clusters, distance_fn) do
    centroids = Enum.map(clusters, &calculate_centroid/1)
    calculate_pairwise_distances(centroids, distance_fn)
  end
end