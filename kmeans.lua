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
  -- TODO
end

-- This function accepts centroids = [{centroid}] and points = [Vec3] and
-- modifies `centroids` into [{centroid, points}].
local function assign_points_to_centroids(centroids, points)
  -- TODO
end

-- This function accepts [{points = [Vec3]}] and returns a sequence [{centroid}]
-- of the centroids of those point sets.
local function find_new_centroids(clusters)
  -- TODO
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
    clusters = find_new_centroids(clusters)
    assign_points_to_centroids(clusters, points)
  end

  return clusters
end


return kmeans
