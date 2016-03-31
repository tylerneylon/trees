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
