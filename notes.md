# Notes on tree generation

## Leaf globs

There are a number of ways to generate leaves. One general approach is
*billboarding*, where many leaves are represented by a single flat sheet that
may include transparency implemented as discarded pixels in the fragment shader.
I'm not an expert at billboarding, but I have the impression that there are many
ways to do it and improve its appearance.

However, I'm more interested in a low-poly look that I think looks cool. In that
direction, I'd like to start with *leaf globs*, by which I mean low-poly
approximations of ellipsoids placed near and encapsulating some of the tree's
leaf points.

### Generating leaf globs

At a high level, I plan to create a spherical glob, then scale it along
arbitrary directions to create an ellipsoid-based glob. The scaling may work by
axis-aligned scaling followed by a random rotation.

Here is the conceptual algorithm I have in mind to generate spherical globs:

    Start:
       Generate a random tetrahedron with points on the unit sphere; do this so
       the sphere's center is included in the tetrahedron.

    Repeat:
       * Pick the largest triangle so far (using the spherical triangle area to
         choose),
       * choose a random point within that triangle and project it onto the
         sphere,
       * use the new point to replace the old triangle with three.

There are a number of tricky points that I anticipate.

When picking the initial tetrahedron, the rays from the sphere's center to the
random points should be linearly independent. The final point needs to be
properly within the anti-projection of the initial points in order for the
sphere's center to be within the tetrahedron properly. I haven't proven this,
but I am moderately confident it's correct based on intuition.

Mathematically, we know what's in a spherical triangle because we can use the
sphere's center as the origin, and then the points define a basis. Things with
all-positive coordinates are in the right hyper-sector of space, and a
projection of any such point onto the sphere will be inside the spherical
triangle we have in mind.

It's also good to note that we can keep an explicit list of triangles as we go.
Otherwise, given just a list of spherical points, I think it may be a challenge
to choose a triangulation of them; or, at least, such an algorithm is not
obvious to me and not necessary with this approach if we track the list as we
go.

To generate a random point on a triangle, we can use a few approaches:

#### Random triangle point appraoch 1

Choose `x, y` uniformly in `[0, 1]`. Avoid degenerate cases `x=0, y=0` or
`x + y = 1`. If `x + y > 1` then use the replacement

    x, y = 1 - x, 1 - y.

The result is a random point in the triangle with points `(0, 0)`, `(1, 0)`, and
`(0, 1)`. This triangle can be mapped to the triangle in mind.

#### Random triangle point approach 2

I was thinking about how to do this in *n* dimensions, since that's what I like.

I *suspect*, but have not yet carefully proven, that the following approach
would work:

    Choose n points uniformly in [0, 1].

    Sort them into x_1 < x_2 < ... < x_n.

    Define y_0, .. , y_n via y_i = x_{i + 1} - x_i, where we consider
    x_0 = 0 and x_{n + 1} = 1.

    Then y_0, .. , y_n are the barycentric coordinates.

I have an audio file with a proof idea (something close to #128).

## Branch shapes

### Canopy symmetry

#### Approach 1

I've noticed that the canopy of leaf points is not well distributed. In
particular, the leaf points appear to be mainly elliptical in shape, whereas I
consider real trees to have more of a circular appearance from above.

I decided to start by trying to approach the 2d tree case first. I'm looking for
a distribution function that is self-reproducing in the sense that two smaller
copies of itself, scaled and added together, recreate the original function.

An easy item to work with is the characteristic function of an interval.

I found another reproducing case in what I call the double-plateau function. It
looks a bit like this:

         ___
     ___/   \___
    /           \

If you space the copies correctly, like this:

         ___
     ___/   \___
    /           \
    
            +
                 ___
             ___/   \___
            /           \

Then the resulting sum has the same general shape, although the relative sizes
of the plateau pieces may change.

Another function that works similarly is to start with g(x) = 1^s where
s = log(2)/log(3), about 0.63092975, and reflect it around x=1 to arrive at a
symmetric hill-like shape.

The sum of two of these matches exactly along the edges, but there is a slight
bump in the middle of the sum. I'm curious to see what further iterations of
this shape turn out to look like.

I also noticed that normal curves look kind of close when added together.

For example, let N_u = exp(-(x-u)^2/2). Then

    N_u ~approximates~ exp(1/8)/2 * (N_{1/2} + N_{-1/2})

Unless I've made a mistake, those curves have the same peak, and not much
difference throughout. I wonder if there are better component pieces available.
I could consider a power series approach.

#### Approach 2

Another line of attack would be to heuristically choose new branch directions
based on existing branch directions as the tree skeleton is built.

When it comes time to add a new fork, I could test out a small number of
candidate directions and choose the one that maximizes the minimum distance to
any existing direction. The easy-to-code approach has this taking n^2 time
overall, however. I could use an LSH approach to cut that down to about n time,
but then the parameters have to be chosen carefully and the code is more
complex.

I have a gut feeling that there's a way to do this that's both efficient and not
insanely hard to code. How does nature do it?

#### Approach 3

The idea here is to essentially pre-assign directions to leaf points in a way
that heuristically distributes them evenly across a hemisphere.

Start with a spiral from the pole of a hemisphere down to the equator, and
identify this with the [0, 1) interval. It can wind around the pole k times, and
we'll put n points on it, evenly distributed within the interval.

I think this is called a Fibonacci lattice:
http://blog.marmakoide.org/?p=1
http://math.stackexchange.com/questions/1358046/

Now, the trunk is associated with the direction at x=0, the pole.

Assign two subsets of directions to the next two branches.

For the first split, they are characterized by bit=0 and bit=1 where this bit is
the first after the value of k is set in the binary representation of the number
in the unit interval.

From here on, alternate between the most-sig binary digit of either the bits
after k, or within k, respectively. So the overall pattern looks like this:

1. Bit split after k.
2. Bit split after k. (one-off starting pattern since it's a hemisphere)
3. Bit split within k.
4. Bit split after k.
5. (etc.) alternat within k, after k, etc.

So the value k needs to be chosen so that this process fits nicely with our
value of n, which, ignoring pruning, would be a power of 2. Allowing for
pruning, we can just leave the early leaf pt where it is.

##### Approach 3.5

Pure approach 3 is not ideal in that it results in too perfect a canopy; too
deterministic. A hybrid approach could offer some variation within the perfect
approach. So, each branching could introduce a little directional variation, and
those variations could add up along the path from the trunk to the leaf point.
In other words, the final leaf point direction would be the ideal direction +
the sum of all adjustments made along the path from the trunk up. This way, leaf
points that are edge-wise close together are likely to have similar directions
that altogether approximate the surface of a sphere.

#### Approach 4

This is the simplest I've thought of so far (besides the current code, which
doesn't really achieve canopy symmetry at all). Just alternate the planes of the
branching splits, so that we avoid an elliptical shape.

#### Questions about canopy symmetry

How does nature solve this? It seems that different tree species tend to have
different characteristic shapes, and even characteristic variations within those
shapes. How does nature determine those shapes?

For example, is the shape pre-determined genetically? It seems there is some
response to gravity and light. But perhaps those only account for self-pruning
and bending.

Is a branch direction determined at the time of branching, or before? Does it
anticipate sunlight or react in retrospect to it? I'm assuming that the best
branch direction is the one that optimizes sunlight exposure to the leaves. Is
that a good assumption?

## Stepping off point

Today is 200.2016, and I've decided to take a haitus from this project. I hope
to return to it within the next several months to a year. My vision is currently
to produce a modest variety of tree shapes that roughly correspond with several
real tree species. I intend to keep the style low-poly and a bit abstract. I'm
interested in modifying both the skeleton shape and branch widths to achieve
that variety. I'm open to trying out new leaf approaches as I'm not sure the
current glob approach will work for many tree types.

I'm recording some ideas here to help myself remember where I was going, and to
get started back in those directions.

A companion document to this is a Pages file called *Self-notes on random tree
generation*. That document includes a draft outline of an article I plan to
write for code_life. I see that as a great goal for this project. That file does
contain some ideas for future work, but I will still list ideas here.

* I'm interested in adding tree growth. If I do this, it may be best to do so
  sooner as I think it will only become more difficult to add over time. I'd
  like to start with non-leaf growth and either add leaf growth later, or never
  at all. It's ok with me if leaf growth is not implemented. I can imagine the
  implementation being a simple growing outward of a skeleton toward its
  precomputed completion. I'm ok if the animation can't be rendered in realtime,
  though I'd love to be able to post-compile an animation or movie file that
  *can* be played in realtime, aka, smoothly.
* Altering the tree skeleton to accommodate different tree species. I imagine
  picking out one species at a time and attempting to generate a skeleton of
  roughly the same shape. I noticed that some tree types appear to have a strong
  trunk throughout their height while others are less centralized, with
  egalitarian branches beyond a certain relatively low point. I've also noticed
  that there seems to be a hierarchy of branch types. Some produce leaves and
  others don't. Some appear flexible or expendable and others don't. Is it
  possible for a branch to move up in this hierarchy?
* Altering the tree skeleton by adding curved branches. I imagine keeping each
  general branch direction the same, but adding a small number of intermediate
  points that add small curves to certain branches. This would involve adding
  rings at those points. I imagine this ring being connected to its neighbors
  similar to the way a child point is connected to its leafward neighbor now.
* Altering branch weights. In some trees, branching points produce two peer-like
  branches. In other cases, the branches are vastly different in scale.
* Exploring color variations. Perhaps different leaf elements could be different
  colors. I can imagine different tree species having different bark colors.
  These colors could be randomized. Different triangles could have slightly
  different base colors. Birch trees have something like stripes. I'm not sure
  how to capture that, but I could think about it. Eucalyptus trees can have
  their own version of stripes that may be easier to capture as
  vertically-oriented patches of similarly-colored triangles, with color
  variation horizontally.
* Completely optionally, I could consider adding more shape variety such as
  saltwater-swept trees like
  [this](https://commons.wikimedia.org/wiki/File:Windswept_tree_on_Brean_Down_(geograph_1902183).jpg)
  or trees with strangely bent trunks like
  [this](http://stunningplaces.net/forest-in-poland/).
