defmodule NoveltySearch.Maze do
  @moduledoc """
  Maze navigation environment for novelty search experiments.
  """

  alias Nx

  defstruct [:width, :height, :walls, :start_pos, :goal_pos, :timesteps]

  @doc """
  Create a new maze from a text representation.
  '*' = wall, ' ' = empty, 'S' = start, 'G' = goal
  """
  def from_string(maze_string, opts \\ []) do
    lines = 
      maze_string
      |> String.trim()
      |> String.split("\n")
    
    height = length(lines)
    width = lines |> Enum.map(&String.length/1) |> Enum.max()
    
    {walls, start_pos, goal_pos} = parse_maze(lines)
    
    %__MODULE__{
      width: width,
      height: height,
      walls: walls,
      start_pos: start_pos,
      goal_pos: goal_pos,
      timesteps: Keyword.get(opts, :timesteps, 400)
    }
  end

  @doc """
  Create a hardcoded medium maze (similar to medium_maze.txt).
  """
  def medium_maze(opts \\ []) do
    maze_string = """
    ********************
    *                  *
    *                  *
    *                  *
    *                  *
    *         *        *
    *         *        *
    *         *        *
    *         *        *
    *         *        *
    *S        *       G*
    ********************
    """
    
    from_string(maze_string, opts)
  end

  @doc """
  Create a hardcoded hard maze (similar to hard_maze.txt).
  """
  def hard_maze(opts \\ []) do
    maze_string = """
    ********************
    *                  *
    *                  *
    *        ***       *
    *        * *       *
    *        * *       *
    *        * *       *
    *        * *       *
    *                  *
    *                  *
    *S                G*
    ********************
    """
    
    from_string(maze_string, opts)
  end

  @doc """
  Simulate a robot navigating the maze using a neural network controller.
  Returns the trajectory and final position.
  """
  def simulate(%__MODULE__{} = maze, network_fn, opts \\ []) do
    max_timesteps = Keyword.get(opts, :max_timesteps, maze.timesteps)
    initial_heading = Keyword.get(opts, :initial_heading, 0.0)
    
    initial_state = %{
      pos: maze.start_pos,
      heading: initial_heading,
      trajectory: [maze.start_pos],
      collision_count: 0
    }
    
    final_state = 
      Enum.reduce(1..max_timesteps, initial_state, fn _step, state ->
        # Get sensor readings with current heading
        sensors = get_sensor_readings(maze, state.pos, state.heading)
        
        # Get network output (left/right wheel velocities)
        outputs = network_fn.(sensors)
        
        # Update position and heading based on outputs
        {new_pos, new_heading} = update_position_and_heading(maze, state.pos, state.heading, outputs)
        
        # Check collision
        collision = if new_pos == state.pos, do: 1, else: 0
        
        %{
          pos: new_pos,
          heading: new_heading,
          trajectory: [new_pos | state.trajectory],
          collision_count: state.collision_count + collision
        }
      end)
    
    %{
      final_pos: final_state.pos,
      trajectory: Enum.reverse(final_state.trajectory),
      collision_count: final_state.collision_count,
      goal_reached: goal_reached?(maze, final_state.pos),
      fitness: calculate_fitness(maze, final_state.pos)
    }
  end

  @doc """
  Extract behavior characterization from simulation result.
  For maze navigation, this is typically the final (x, y) position.
  """
  def behavior_characterization(sim_result) do
    {x, y} = sim_result.final_pos
    [x, y]
  end

  # Private functions

  defp parse_maze(lines) do
    {walls, start_pos, goal_pos} = 
      lines
      |> Enum.with_index()
      |> Enum.reduce({[], nil, nil}, fn {line, y}, {walls_acc, start_acc, goal_acc} ->
        line
        |> String.graphemes()
        |> Enum.with_index()
        |> Enum.reduce({walls_acc, start_acc, goal_acc}, fn {char, x}, {w, s, g} ->
          case char do
            "*" -> {[{x, y} | w], s, g}
            "S" -> {w, {x, y}, g}
            "G" -> {w, s, {x, y}}
            _ -> {w, s, g}
          end
        end)
      end)
    
    {MapSet.new(walls), start_pos, goal_pos}
  end

  defp get_sensor_readings(%__MODULE__{} = maze, {x, y}, heading) do
    # Rangefinder sensors at specific angles (matching C++ implementation)
    rangefinder_angles = [-90, -45, 0, 45, 90, -180]  # 6 sensors like C++
    rangefinder_range = 100.0
    
    # Calculate rangefinder readings
    rangefinder_readings = 
      Enum.map(rangefinder_angles, fn relative_angle ->
        absolute_angle = heading + relative_angle * :math.pi() / 180.0
        dx = :math.cos(absolute_angle)
        dy = :math.sin(absolute_angle)
        
        distance = find_wall_distance_precise(maze, {x, y}, {dx, dy}, rangefinder_range)
        distance / rangefinder_range  # Normalize to [0, 1]
      end)
    
    # Radar sensors for goal detection (4 quadrants like C++)
    radar_readings = get_radar_readings(maze, {x, y}, heading)
    
    # Combine bias, rangefinders, and radar sensors (total 11 inputs like C++)
    [1.0] ++ rangefinder_readings ++ radar_readings
  end

  defp get_radar_readings(%__MODULE__{} = maze, {x, y}, heading) do
    {gx, gy} = maze.goal_pos
    goal_absolute_angle = :math.atan2(gy - y, gx - x) * 180.0 / :math.pi()
    goal_relative_angle = normalize_angle_degrees(goal_absolute_angle - heading * 180.0 / :math.pi())
    
    # Convert to 0-360 range for quadrant detection
    normalized_angle = if goal_relative_angle < 0, do: goal_relative_angle + 360, else: goal_relative_angle
    
    # 4 radar quadrants (matching C++ implementation)
    quadrants = [
      {315, 405},  # Front-right (wrapping around)
      {45, 135},   # Front-left  
      {135, 225},  # Back-left
      {225, 315}   # Back-right
    ]
    
    Enum.map(quadrants, fn {start_angle, end_angle} ->
      if (normalized_angle >= start_angle and normalized_angle <= end_angle) or
         (start_angle > end_angle and (normalized_angle >= start_angle or normalized_angle <= rem(end_angle, 360))) do
        1.0
      else
        0.0
      end
    end)
  end

  defp normalize_angle_degrees(angle) do
    # Normalize angle to [-180, 180] degrees
    angle = angle - 360.0 * Float.floor(angle / 360.0)
    cond do
      angle > 180.0 -> angle - 360.0
      angle < -180.0 -> angle + 360.0
      true -> angle
    end
  end

  defp find_wall_distance_precise(%__MODULE__{} = maze, {x, y}, {dx, dy}, max_range) do
    # Create sensor ray from current position in the given direction
    end_x = x + dx * max_range
    end_y = y + dy * max_range
    sensor_ray = {{x, y}, {end_x, end_y}}
    
    # Find closest intersection with any wall segment
    closest_distance = 
      maze.walls
      |> MapSet.to_list()
      |> Enum.map(&wall_cell_to_segments/1)
      |> List.flatten()
      |> Enum.reduce(max_range, fn wall_segment, min_dist ->
        case line_intersection(sensor_ray, wall_segment) do
          {:ok, {int_x, int_y}} ->
            distance = :math.sqrt(:math.pow(int_x - x, 2) + :math.pow(int_y - y, 2))
            min(distance, min_dist)
          :no_intersection ->
            min_dist
        end
      end)
    
    closest_distance
  end

  # Convert a wall cell position to line segments (4 edges of the cell)
  defp wall_cell_to_segments({wx, wy}) do
    [
      {{wx, wy}, {wx + 1, wy}},        # Top edge
      {{wx + 1, wy}, {wx + 1, wy + 1}}, # Right edge  
      {{wx + 1, wy + 1}, {wx, wy + 1}}, # Bottom edge
      {{wx, wy + 1}, {wx, wy}}         # Left edge
    ]
  end

  # Line-line intersection using parametric equations (like C++ implementation)
  defp line_intersection({{x1, y1}, {x2, y2}}, {{x3, y3}, {x4, y4}}) do
    # Calculate direction vectors
    dx1 = x2 - x1
    dy1 = y2 - y1
    dx2 = x4 - x3
    dy2 = y4 - y3
    
    # Calculate determinant
    det = dx1 * dy2 - dy1 * dx2
    
    if abs(det) < 1.0e-10 do
      # Lines are parallel
      :no_intersection
    else
      # Calculate parameters
      dx3 = x1 - x3
      dy3 = y1 - y3
      
      t1 = (dx2 * dy3 - dy2 * dx3) / det
      t2 = (dx1 * dy3 - dy1 * dx3) / det
      
      # Check if intersection is within both line segments
      if t1 >= 0 and t1 <= 1 and t2 >= 0 and t2 <= 1 do
        # Calculate intersection point
        int_x = x1 + t1 * dx1
        int_y = y1 + t1 * dy1
        {:ok, {int_x, int_y}}
      else
        :no_intersection
      end
    end
  end

  defp wall_at?(%__MODULE__{} = maze, {x, y}) do
    int_x = round(x)
    int_y = round(y)
    
    MapSet.member?(maze.walls, {int_x, int_y})
  end

  defp update_position_and_heading(%__MODULE__{} = maze, {x, y}, heading, outputs) do
    # outputs should be [angular_velocity_delta, speed_delta] (matching C++ interpretation)
    [o1, o2] = Enum.take(outputs, 2)
    
    # Convert outputs from [0,1] to [-0.5, 0.5] and apply to robot (like C++)
    ang_vel_delta = (o1 - 0.5) * 1.0
    speed_delta = (o2 - 0.5) * 1.0
    
    # Apply speed and angular velocity constraints (matching C++ limits)
    max_speed = 3.0
    max_ang_vel = 3.0
    
    # Calculate new velocities (would need to track current velocities in full implementation)
    # For now, directly use the deltas as velocities
    linear_velocity = clamp(speed_delta, -max_speed, max_speed)
    angular_velocity = clamp(ang_vel_delta, -max_ang_vel, max_ang_vel)
    
    # Convert angular velocity from degrees to radians per timestep
    angular_velocity_rad = angular_velocity * :math.pi() / 180.0
    
    # Update heading first
    new_heading = normalize_angle(heading + angular_velocity_rad)
    
    # Calculate movement in world coordinates using new heading
    dx = :math.cos(new_heading) * linear_velocity
    dy = :math.sin(new_heading) * linear_velocity
    
    new_x = x + dx
    new_y = y + dy
    
    # Simple point-based collision detection (robot center point only)
    int_x = round(new_x)
    int_y = round(new_y)
    
    if MapSet.member?(maze.walls, {int_x, int_y}) or 
       int_x < 0 or int_x >= maze.width or int_y < 0 or int_y >= maze.height do
      {{x, y}, new_heading}  # Stay in place if collision, but update heading
    else
      {{new_x, new_y}, new_heading}
    end
  end

  defp clamp(value, min_val, max_val) do
    cond do
      value < min_val -> min_val
      value > max_val -> max_val
      true -> value
    end
  end

  defp collision_with_walls?(%__MODULE__{} = maze, {x, y}, radius) do
    # Check if robot circle intersects with any wall segments
    maze.walls
    |> MapSet.to_list()
    |> Enum.map(&wall_cell_to_segments/1)
    |> List.flatten()
    |> Enum.any?(fn wall_segment ->
      distance_point_to_line_segment({x, y}, wall_segment) < radius
    end)
  end

  defp distance_point_to_line_segment({px, py}, {{x1, y1}, {x2, y2}}) do
    # Calculate distance from point to line segment (matching C++ algorithm)
    dx = x2 - x1
    dy = y2 - y1
    
    if dx == 0 and dy == 0 do
      # Line segment is a point
      :math.sqrt(:math.pow(px - x1, 2) + :math.pow(py - y1, 2))
    else
      # Calculate parameter t for projection onto line
      t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
      
      cond do
        t < 0 ->
          # Point projects before start of segment
          :math.sqrt(:math.pow(px - x1, 2) + :math.pow(py - y1, 2))
        t > 1 ->
          # Point projects after end of segment  
          :math.sqrt(:math.pow(px - x2, 2) + :math.pow(py - y2, 2))
        true ->
          # Point projects onto segment
          proj_x = x1 + t * dx
          proj_y = y1 + t * dy
          :math.sqrt(:math.pow(px - proj_x, 2) + :math.pow(py - proj_y, 2))
      end
    end
  end

  defp normalize_angle(angle) do
    # Normalize angle to [-π, π]
    two_pi = 2 * :math.pi()
    angle = angle - two_pi * Float.floor(angle / two_pi)
    cond do
      angle > :math.pi() -> angle - two_pi
      angle < -:math.pi() -> angle + two_pi
      true -> angle
    end
  end

  defp out_of_bounds?(%__MODULE__{} = maze, {x, y}) do
    x < 0 or x >= maze.width or y < 0 or y >= maze.height
  end

  defp goal_reached?(%__MODULE__{} = maze, {x, y}) do
    {gx, gy} = maze.goal_pos
    distance = :math.sqrt(:math.pow(gx - x, 2) + :math.pow(gy - y, 2))
    distance < 5.0  # Within 5 units of goal
  end

  defp calculate_fitness(%__MODULE__{} = maze, {x, y}) do
    {gx, gy} = maze.goal_pos
    distance = :math.sqrt(:math.pow(gx - x, 2) + :math.pow(gy - y, 2))
    
    # Fitness is inverse of distance to goal
    1.0 / (1.0 + distance)
  end
end