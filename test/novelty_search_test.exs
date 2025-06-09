defmodule NoveltySearchTest do
  use ExUnit.Case
  
  alias NoveltySearch.{Core, Maze, Behaviors}

  describe "Core novelty search" do
    test "calculates novelty score correctly" do
      ns = Core.new(k_nearest: 3)
      
      behavior = [5.0, 5.0]
      population_behaviors = [
        [0.0, 0.0],
        [10.0, 10.0],
        [3.0, 3.0],
        [7.0, 7.0],
        [1.0, 1.0]
      ]
      
      score = Core.novelty_score(ns, behavior, population_behaviors)
      
      # Score should be average distance to 3 nearest neighbors
      assert score > 0
      assert score < 10
    end

    test "updates archive based on threshold" do
      ns = Core.new(archive_threshold: 5.0, min_dist_to_archive: 2.0)
      
      behaviors = [[0.0, 0.0], [10.0, 10.0], [5.0, 5.0]]
      scores = [3.0, 7.0, 6.0]  # Only last two meet threshold
      
      updated_ns = Core.update_archive(ns, behaviors, scores)
      
      assert length(updated_ns.archive) == 2
      assert [10.0, 10.0] in updated_ns.archive
      assert [5.0, 5.0] in updated_ns.archive
    end

    test "respects minimum distance to archive" do
      ns = Core.new(
        archive_threshold: 1.0, 
        min_dist_to_archive: 5.0,
        archive: [[0.0, 0.0]]
      )
      
      behaviors = [[1.0, 1.0], [10.0, 10.0]]  # First too close, second far enough
      scores = [10.0, 10.0]  # Both high scores
      
      updated_ns = Core.update_archive(ns, behaviors, scores)
      
      assert length(updated_ns.archive) == 2  # Original + one new
      assert [10.0, 10.0] in updated_ns.archive
      refute [1.0, 1.0] in updated_ns.archive
    end
  end

  describe "Maze environment" do
    test "creates maze from string" do
      maze_string = "*****\n*S G*\n*****"
      
      maze = Maze.from_string(maze_string)
      
      assert maze.width == 5
      assert maze.height == 3
      assert maze.start_pos == {1, 1}
      assert maze.goal_pos == {3, 1}
    end

    test "simulates robot movement" do
      # Simple test with no collision detection for now
      maze = Maze.from_string("*****\n*S G*\n*****")
      
      # Simple controller that moves forward 
      network_fn = fn _sensors -> [0.0, 1.0] end  # No turn, full forward movement
      
      result = Maze.simulate(maze, network_fn, max_timesteps: 2)
      
      # Should move at least slightly from start position
      {start_x, start_y} = maze.start_pos
      {final_x, final_y} = result.final_pos
      
      # Check that robot moved (floating point position should be different)
      movement_distance = :math.sqrt((final_x - start_x) * (final_x - start_x) + (final_y - start_y) * (final_y - start_y))
      assert movement_distance > 0.1  # Moved at least 0.1 units
      assert length(result.trajectory) == 3  # Initial + 2 steps
    end

    test "behavior characterization extracts final position" do
      sim_result = %{
        final_pos: {5.5, 7.2},
        trajectory: [{0, 0}, {5.5, 7.2}]
      }
      
      behavior = Maze.behavior_characterization(sim_result)
      
      assert behavior == [5.5, 7.2]
    end
  end

  describe "Behavior characterizations" do
    test "euclidean distance calculation" do
      b1 = [0.0, 0.0]
      b2 = [3.0, 4.0]
      
      distance = Behaviors.euclidean_distance(b1, b2)
      
      assert_in_delta distance, 5.0, 0.01
    end

    test "trajectory behavior sampling" do
      trajectory = [
        {0, 0}, {1, 1}, {2, 2}, {3, 3}, {4, 4},
        {5, 5}, {6, 6}, {7, 7}, {8, 8}, {9, 9}
      ]
      
      behavior = Behaviors.trajectory_behavior(trajectory, 5)
      
      # Should have 5 points * 2 coordinates = 10 values
      # Sampling indices: 0, 2, 5, 7, 9 (due to rounding in the algorithm)
      assert length(behavior) == 10
      assert behavior == [0, 0, 2, 2, 5, 5, 7, 7, 9, 9]
    end

    test "grid occupancy behavior" do
      trajectory = [
        {0.5, 0.5}, {1.5, 0.5}, {2.5, 1.5}, {2.5, 2.5}
      ]
      
      behavior = Behaviors.grid_occupancy_behavior(trajectory, {3, 3})
      
      # 3x3 grid = 9 cells
      assert length(behavior) == 9
      
      # Check occupied cells
      expected_grid = [
        1, 1, 0,  # Row 0: cells (0,0) and (1,0) visited
        0, 0, 1,  # Row 1: cell (2,1) visited
        0, 0, 1   # Row 2: cell (2,2) visited
      ]
      
      assert behavior == expected_grid
    end

    test "multi-objective behavior normalization" do
      features = %{
        distance_traveled: 50,
        energy_used: 25,
        final_x: 0,
        final_y: -25
      }
      
      behavior = Behaviors.multi_objective_behavior(features)
      
      # All values should be normalized to [0, 1]
      assert length(behavior) == 4
      assert Enum.all?(behavior, &(&1 >= 0 and &1 <= 1))
    end
  end

  describe "Integration" do
    test "runs maze experiment successfully" do
      # Small test run
      result = NoveltySearch.NEATIntegration.run_maze_experiment(
        :medium,
        generations: 2,
        population_size: 10
      )
      
      assert is_map(result)
      assert length(result.final_population) == 10
      assert is_list(result.archive)
      assert length(result.history) == 2
    end
  end
end