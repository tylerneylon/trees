--[[

kmeans.lua

K-means clustering.

--]]

local kmeans = {}


-- Requires.

local Vec3 = require 'Vec3'


-- Internal functions.

-- This returns a sequence of k distinct indexes in the range [1, n] chosen so
-- that, within the context of the pseudorandom generator, each k-subset has an
-- equal probability of being returned.
local function random_indexes(k, n)
  -- This is a partial Fisher-Yates shuffle, as suggested by this answer:
  -- http://stackoverflow.com/a/29868630/3561
  local shuf    = {}
  local indexes = {}
  for i = 1, k do
    local j = math.random(i, n)
    shuf[i], shuf[j] = (shuf[j] or j), (shuf[i] or i)
    indexes[i] = shuf[i]
  end
  return indexes
end

-- This function accepts centroids = [{centroid}] and points = [Vec3] and
-- modifies `centroids` into [{centroid, points}].
local function assign_points_to_centroids(centroids, points)

  -- Ensure each cluster has a points sequence.
  for _, cluster in pairs(centroids) do
    cluster.points = {}
  end

  -- Assign each point to its closest centroid.
  for _, pt in pairs(points) do
    local best_dist    = math.huge
    local best_cluster = nil
    for _, cluster in pairs(centroids) do
      local d = (cluster.centroid - pt):length()
      if d < best_dist then
        best_dist, best_cluster = d, cluster
      end
    end
    table.insert(best_cluster.points, pt)
  end
end

-- This function accepts [{points = [Vec3]}] and adds the new key `centroid`
-- alongside each `points` key; the `centroid` value is the centroid Vec3 point
-- of the corresponding `points` array.
local function find_new_centroids(clusters)
  for _, cluster in pairs(clusters) do
    local sum = Vec3:new(0, 0, 0)
    for _, pt in pairs(cluster.points) do
      sum = sum + pt
    end
    cluster.centroid = sum / #cluster.points
  end
end

-- Public functions.

-- This function expects a sequence of Vec3 points as input.
-- It returns a sequence of clusters. Each cluster has the format:
-- cluster = {centroid, points},
-- where `cluster.points` is a subset of the input `points` sequence.
function kmeans.find_clusters(points, k, num_iters)
  k = k or 5
  num_iters = num_iters or 10

  local init_indexes = random_indexes(k, #points)
  local clusters = {}
  for i = 1, k do
    clusters[#clusters + 1] = {centroid = points[init_indexes[i]]}
  end
  assign_points_to_centroids(clusters, points)

  for i = 1, num_iters do
    find_new_centroids(clusters)
    assign_points_to_centroids(clusters, points)
  end

  return clusters
end


return kmeans
