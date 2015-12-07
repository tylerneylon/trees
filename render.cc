#include "render.h"

extern "C" {
#include "cstructs/cstructs.h"
#include "glhelp.h"
}

#include <OpenGL/gl3.h>

#include "glm.hpp"
#define GLM_FORCE_RADIANS
#include "matrix_transform.hpp"
using namespace glm;

extern "C" {
#include "file.h"
  
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

#include <stdio.h>

#define max_tree_height 10
#define zoom_scale 2.3
#define branch_size_factor 0.79
#define max_ring_corners 8


// Internal types and globals.

typedef enum {
  pt_type_leaf,
  pt_type_parent,
  pt_type_child
} Pt_type;

typedef struct {
  Pt_type pt_type;
  int parent;
  int child1, child2;
  int ring_start, ring_end;  // The ring_end is excluded.
  float ring_radius;
  int ring_pt_of_top0;  // Used for child points only.
} Pt_info;

static GLuint line_program, bark_program;
static GLuint vao;
static GLuint vbo;

static mat4 model;
static mat4 view;

static int num_pts;

static CArray tree_pts     = NULL;
static CArray tree_pt_info = NULL;

// These are triples of ints, indices into tree_pts.
// Each triple is (trunk_end, branch1, branch2).
static CArray branch_pts = NULL;

static CArray leaves = NULL;

static CArray ring_pts = NULL;

static bool do_draw_skeleton    = false;
static bool do_draw_rings       = false;
static bool do_draw_stick_lines = false;
static bool do_draw_stick_bark  = true;
static bool do_draw_joint_bark  = true;

static GLuint rings_vao;

static GLvoid *stick_line_elts;
static GLsizei num_stick_line_elts;
static GLuint stick_lines_vbo;

static GLuint stick_bark_vbo;
static CArray stick_bark_pts     = NULL;
static CArray stick_bark_normals = NULL;
static GLuint stick_bark_normal_vbo;

static GLuint joint_bark_vbo;
static CArray joint_bark_pts     = NULL;
static CArray joint_bark_normals = NULL;
static GLuint joint_bark_normal_vbo;

static GLuint restart_index;


// Internal functions.

static void set_buffer_data(CArray arr) {
  glBufferData(GL_ARRAY_BUFFER,
               arr->count * arr->elementSize,
               arr->elements,
               GL_STATIC_DRAW);
}

static void set_3f_attrib(GLuint index) {
  glVertexAttribPointer(index, 3, GL_FLOAT, GL_FALSE, 0, NULL);
  glEnableVertexAttribArray(index);
}

static void *get_vertices(GLsizeiptr *data_size, int *pt_count) {
  static GLfloat vertices[] = {
     0.0, 0.0, 0.0,
     0.0, 1.0, 0.0,
    -0.3, 1.0, 0.0,
    -0.3, 1.3, 0.0,
    -0.3, 1.3, 0.3,
    -0.3, 1.6, 0.3
  };
  
  *data_size = sizeof(vertices);
  
  *pt_count = sizeof(vertices) / sizeof(GLfloat) / 3;
  
  return vertices;
}

static float uniform_rand(float min, float max) {
  float r = (float)rand() / RAND_MAX;
  return r * (max - min) + min;
}

static float val_near_avg(float avg_len) {
  return uniform_rand(avg_len * 0.85, avg_len * 1.15);
}

static void add_line(vec3 start, vec3 end, int parent_index) {
  
  // Both CArrayAddElement lines add all three coordinates to the array.
  // I wish this was more obvious from the code itself.
  
  CArrayAddElement(tree_pts, start[0]);
  *(Pt_info *)CArrayNewElement(tree_pt_info) = (Pt_info) { .pt_type = pt_type_child, .parent = parent_index };
  
  CArrayAddElement(tree_pts,   end[0]);
  *(Pt_info *)CArrayNewElement(tree_pt_info) = (Pt_info) { .pt_type = pt_type_leaf };
  
}

static char *vec_str(vec3 v) {
  static char s[64];
  sprintf(s, "(%g, %g, %g)", v.x, v.y, v.z);
  return s;
}

static void add_to_tree(vec3 origin,
                        vec3 direction,
                        float weight,
                        float avg_len,
                        float min_len,
                        int max_recursion,
                        int parent_index) {
 
  direction = normalize(direction);
  
  float len = val_near_avg(avg_len);
  
  add_line(origin, origin + len * direction, parent_index);
  
  if (len < min_len || max_recursion == 0) {
    *(int *)CArrayNewElement(leaves) = tree_pts->count - 1;
    return;
  }
  
  avg_len = avg_len * branch_size_factor;
  origin += len * direction;
  parent_index = tree_pts->count - 1;
  
  float w1 = val_near_avg(0.5);
  float w2 = 1.0 - w1;
  
  float split_angle = val_near_avg(0.55);
  float turn_angle = uniform_rand(0.0, 2 * M_PI);
  
  // Find other_dir orthogonal to direction.
  
  vec3 arbit_dir = vec3(1, 0, 0);
  
  // Avoid stability problems by making sure arbit_dir is far from a scalar of direction.
  if (direction.x > direction.y && direction.x > direction.z) arbit_dir = vec3(0, 1, 0);
  
  vec3 other_dir = cross(direction, arbit_dir);
  
  mat4 turn = rotate(mat4(1), turn_angle, direction);
  
  // It is correct that we use w2 as the weight for dir1, and w1 for dir2.
  vec3 dir1 = vec3(turn * rotate(mat4(1),  split_angle * w2, other_dir) * vec4(direction, 0));
  vec3 dir2 = vec3(turn * rotate(mat4(1), -split_angle * w1, other_dir) * vec4(direction, 0));

  if (branch_pts == NULL) branch_pts = CArrayNew(0, sizeof(int));
  
  int tree_pt = tree_pts->count - 3;  // Index of last point; each point has 3 coordinates.
  CArrayAddElement(branch_pts, tree_pt);
  tree_pt += 3;
  CArrayAddElement(branch_pts, tree_pt);
  CArrayAddElement(branch_pts, tree_pt);  // This last one is a placeholder for now.
  int second_branch_pt_index = branch_pts->count - 1;
  
  Pt_info *parent_info = (Pt_info *)CArrayElement(tree_pt_info, parent_index);
  parent_info->pt_type = pt_type_parent;
  
  parent_info->child1  = tree_pts->count;
  add_to_tree(origin, dir1, w1, avg_len, min_len, max_recursion - 1, parent_index);

  // The next-added tree_pt will be the second branch instance of this branch pt.
  CArrayElementOfType(branch_pts, second_branch_pt_index, int) = tree_pts->count;
  
  parent_info = (Pt_info *)CArrayElement(tree_pt_info, parent_index);
  parent_info->child2 = tree_pts->count;
  add_to_tree(origin, dir2, w2, avg_len, min_len, max_recursion - 1, parent_index);
  
}

static float pt_dist(CArray pts, int i1, int i2) {
  GLfloat *pt1 = (GLfloat *)CArrayElement(pts, i1);
  GLfloat *pt2 = (GLfloat *)CArrayElement(pts, i2);
  
  GLfloat d[3];
  for (int i = 0; i < 3; ++i) d[i] = pt1[i] - pt2[i];
  return sqrtf(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
}

// Returns the distance from the center to any corner.
// It's not a circle, so this is different from the distance from the center
// to any other point along the ring.
static float get_ring_radius_from_part_size(float ring_part_size, int num_ring_corners) {
  float alpha = M_PI * (0.5 - 1.0 / num_ring_corners);
  return ring_part_size / (2 * cos(alpha));
}

static void get_pt(CArray pts, int index, vec3 &pt) {
  GLfloat *pt_vals = (GLfloat *)CArrayElement(pts, index);
  for (int i = 0; i < 3; ++i) pt[i] = pt_vals[i];
}

static void set_pt(CArray pts, int index, vec3 &pt) {
  GLfloat *pt_vals = (GLfloat *)CArrayElement(pts, index);
  for (int i = 0; i < 3; ++i) pt_vals[i] = pt[i];
}

static void complete_ring(vec3 &upward, vec3 &center, vec3 &to_pt0, int num_ring_corners, int skip_pts) {
  
  float angle = 2.0 * M_PI / num_ring_corners;
  
  mat4 rot   = rotate(mat4(1), angle, upward);
  vec3 to_pt = to_pt0;
  
  for (int i = 0; i < num_ring_corners; ++i) {
    
    if (i >= skip_pts) {
      vec3 pt = center + to_pt;
      CArrayAddElement(ring_pts, pt[0]);
    }
    to_pt = vec3(rot * vec4(to_pt, 0));
    
  }
  
}

// Completes the ring started from the last two points in ring_pts.
// The ring_part_size is inferred from the first two points.
static void complete_ring_from_two_points(vec3 &upward, int num_ring_corners) {
  
  float ring_part_size = pt_dist(ring_pts, ring_pts->count - 2, ring_pts->count - 1);
  float radius = get_ring_radius_from_part_size(ring_part_size, num_ring_corners);
  
  float hrps = ring_part_size / 2.0;  // hrps = half of ring_part_size.
  float midpart_center_dist = sqrtf(radius * radius - hrps * hrps);
  
  vec3 pt0, pt1;
  get_pt(ring_pts, ring_pts->count - 2, pt0);
  get_pt(ring_pts, ring_pts->count - 1, pt1);
  vec3 to_center = midpart_center_dist * normalize(cross(upward, pt1 - pt0));
  vec3 center = 0.5f * pt0 + 0.5f * pt1 + to_center;
  
  // TODO standardize the name to_pt0
  
  vec3 to_pt0 = pt0 - center;
  
  complete_ring(upward, center, to_pt0, num_ring_corners, 2);
  
}

// Completes the ring started by the last point in ring_pts.
static void complete_ring_from_one_point(vec3 &upward, vec3 &ring_center, int num_ring_corners, float ring_part_size) {
  
  GLfloat *pt1_vals = (GLfloat *)CArrayElement(ring_pts, ring_pts->count - 1);
  vec3     pt1      = vec3(pt1_vals[0], pt1_vals[1], pt1_vals[2]);
  vec3  to_pt1      = pt1 - ring_center;
  
  complete_ring(upward, ring_center, to_pt1, num_ring_corners, 1);
  
}

static void find_upward(int index, vec3 &upward) {
  
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, index);
  
  int   to_index = index;
  int from_index = index - 1;
  
  if (pt_info->pt_type == pt_type_child) {
    to_index   = index + 1;
    from_index = index;
  }
  
  GLfloat *from = (GLfloat *)CArrayElement(tree_pts, from_index);
  GLfloat *  to = (GLfloat *)CArrayElement(tree_pts,   to_index);
  
  for (int i = 0; i < 3; ++i) upward[i] = to[i] - from[i];
}

// The center will be adjusted slightly up or down depending on the point type.
// This does nothing special for the trunk. It's only designed for regular child or parent points.
static void find_ring_center(int index, vec3 &v) {
  
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, index);
  
  GLfloat *tr_pt = (GLfloat *)CArrayElement(tree_pts, index);
  vec3 tree_pt = vec3(tr_pt[0], tr_pt[1], tr_pt[2]);
  
  vec3 upward;
  find_upward(index, upward);
  
  // TODO Make sure this sends out v as wanted.
  if (pt_info->pt_type == pt_type_child) {
    v = tree_pt + 0.4f * upward;
  } else {
    v = tree_pt - 0.05f * upward;
  }
}

static void add_ring_to_child(int child_index, int num_ring_corners, float scale);

static void add_ring_to_parent(int parent_index) {
  
  //printf("%s(%d)\n", __func__, parent_index);
  
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, parent_index);
  
  // How many ring corners does the child joint have?
  Pt_info *child1_info = (Pt_info *)CArrayElement(tree_pt_info, pt_info->child1);
  Pt_info *child2_info = (Pt_info *)CArrayElement(tree_pt_info, pt_info->child2);
  int child1_corners = child1_info->ring_end - child1_info->ring_start;
  int child2_corners = child2_info->ring_end - child2_info->ring_start;
  int child_ring_corners = child1_corners + child2_corners - 2;
  
  int num_ring_corners = child_ring_corners > max_ring_corners ? max_ring_corners : child_ring_corners;
  
  // What is the scale of this ring?
  float stick_len = pt_dist(tree_pts, parent_index, parent_index - 1);
  float bottom_ring_part_size = 1.0 * stick_len / num_ring_corners;
  
  float top_ring_part_size1 = pt_dist(ring_pts, child1_info->ring_start, child1_info->ring_start + 1);
  float top_ring_part_size2 = pt_dist(ring_pts, child2_info->ring_start, child2_info->ring_start + 1);
  float top_ring_part_size  = 0.5 * top_ring_part_size1 + 0.5 * top_ring_part_size2;
  
  float ring_part_size = 0.9 * top_ring_part_size + 0.1 * bottom_ring_part_size;
  
  vec3 ring_center;
  find_ring_center(parent_index, ring_center);
  
  vec3 upward;
  find_upward(parent_index, upward);
  upward = normalize(upward);  // We'd like this as a unit vector to easily project away from it below.
  
  // TODO
  // * Make tree_pts a global instead of passing it around everywhere.
  // * Make it easier to get a vec3 out of either tree_pts or ring_pts.
  
  // Set up the first point.
  GLfloat *ch_pt = (GLfloat *)CArrayElement(ring_pts, child1_info->ring_start + 1);
  vec3 child_pt = vec3(ch_pt[0], ch_pt[1], ch_pt[2]);
  vec3 to_child_pt = child_pt - ring_center;
  // Project child_pt onto the plane perpendicular to upward.
  vec3 first_pt_dir = normalize(to_child_pt - upward * dot(to_child_pt, upward));
  float ring_radius = get_ring_radius_from_part_size(ring_part_size, num_ring_corners);
  vec3 first_pt = ring_center + ring_radius * first_pt_dir;
  
  pt_info->ring_start = ring_pts->count;
  CArrayAddElement(ring_pts, first_pt[0]);
  complete_ring_from_one_point(upward, ring_center, num_ring_corners, ring_part_size);
  pt_info->ring_end = ring_pts->count;
  
  pt_info->ring_radius = ring_radius;
  
  add_ring_to_child(parent_index - 1, num_ring_corners, stick_len);
}

static void set_ring_pt_of_top0(int child_index) {
  
  Pt_info *    pt_info = (Pt_info *)CArrayElement(tree_pt_info, child_index);
  Pt_info *top_pt_info = (Pt_info *)CArrayElement(tree_pt_info, child_index + 1);
  
  vec3 top0;
  get_pt(ring_pts, top_pt_info->ring_start, top0);
  
  vec3 bottom_pt, top_pt;
  get_pt(tree_pts, child_index,  bottom_pt);
  get_pt(tree_pts, child_index + 1, top_pt);
  
  vec3 top0_shadow = top0 + bottom_pt - top_pt;
  vec3 local_pt;
  get_pt(ring_pts, pt_info->ring_start, local_pt);
  
  float min_dist = distance(top0_shadow, local_pt);
  pt_info->ring_pt_of_top0 = pt_info->ring_start;
  
  for (int r_index = pt_info->ring_start + 1; r_index < pt_info->ring_end; ++r_index) {
    
    get_pt(ring_pts, r_index, local_pt);
    float d = distance(top0_shadow, local_pt);
    if (d < min_dist) {
      min_dist = d;
      pt_info->ring_pt_of_top0 = r_index;
    }
    
  }
  
}

// This does the same thing as add_ring_to_index, but it only handles the special case
// when the given index is the index of a child (hence the name child_index).
static void add_ring_to_child(int child_index, int num_ring_corners, float scale) {
  
  //printf("%s(%d)\n", __func__, child_index);
  
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, child_index);
  
  vec3 upward;
  find_upward(child_index, upward);
  
  float ring_part_size = 0.7 * scale / num_ring_corners;
  
  // Treat the root point as a special case.
  if (pt_info->parent == -1) {
    
    GLfloat *tr_pt = (GLfloat *)CArrayElement(tree_pts, child_index);
    vec3 trunk_pt = vec3(tr_pt[0], tr_pt[1], tr_pt[2]);
    
    vec3 outward = vec3(1, 0, 0);  // Guaranteed to be orth to upward since upward is (0, 1, 0).
    float radius = get_ring_radius_from_part_size(ring_part_size, num_ring_corners);
    vec3 first_pt = trunk_pt + radius * outward;
    
    pt_info->ring_start = ring_pts->count;
    CArrayAddElement(ring_pts, first_pt[0]);
    complete_ring_from_one_point(upward, trunk_pt, num_ring_corners, ring_part_size);
    pt_info->ring_end   = ring_pts->count;
    
    pt_info->ring_radius = radius;
    set_ring_pt_of_top0(child_index);
    
    return;
    
  }
  
  // Find our sibling.
  Pt_info *parent_info  = (Pt_info *)CArrayElement(tree_pt_info, pt_info->parent);
  int sibling_index     = parent_info->child1 ^ parent_info->child2 ^ child_index;
  Pt_info *sibling_info = (Pt_info *)CArrayElement(tree_pt_info, sibling_index);
  
  
  // Check if the sibling already has a ring.
  if (sibling_info->ring_end > 0) {
    
    int sibling_start = sibling_info->ring_start;
    pt_info->ring_start = ring_pts->count;
    CArrayAddElementByPointer(ring_pts, CArrayElement(ring_pts, sibling_start + 1));
    CArrayAddElementByPointer(ring_pts, CArrayElement(ring_pts, sibling_start));
    complete_ring_from_two_points(upward, num_ring_corners);
    pt_info->ring_end = ring_pts->count;
    
    pt_info->ring_radius = 0;
    set_ring_pt_of_top0(child_index);
    
    add_ring_to_parent(pt_info->parent);
    
    return;
    
  }
  
  // There's no sibling ring yet; we must find the first two points ourselves.
  
  vec3  my_center, sibling_center;
  find_ring_center(  child_index,      my_center);
  find_ring_center(sibling_index, sibling_center);
  
  // Find the first two points.
  vec3 joint_center = 0.5f * my_center + 0.5f * sibling_center;
  vec3 parent_upward;
  find_upward(pt_info->parent, parent_upward);
  vec3 to_first_pt = normalize(cross(parent_upward, my_center - sibling_center));
  //float radius = get_ring_radius_from_part_size(ring_part_size, num_ring_corners);
  vec3  first_pt = joint_center + ring_part_size * 0.5f * to_first_pt;
  vec3 second_pt = joint_center - ring_part_size * 0.5f * to_first_pt;
  
  // Set up the ring itself.
  pt_info->ring_start = ring_pts->count;
  CArrayAddElement(ring_pts,  first_pt[0]);
  CArrayAddElement(ring_pts, second_pt[0]);
  complete_ring_from_two_points(upward, num_ring_corners);
  pt_info->ring_end = ring_pts->count;
  
  pt_info->ring_radius = get_ring_radius_from_part_size(ring_part_size, num_ring_corners);
  set_ring_pt_of_top0(child_index);
}

// Add a ring at a specific index which is guaranteed to be "ready".
// Being ready means that its children both have rings already set up.
// This function goes as far down the tree as it can until it hits a non-ready index.
static void add_ring_at_index(int index, int num_ring_corners, float scale) {
  
  //printf("%s(%d)\n", __func__, index);
  
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, index);
  
  if (pt_info->pt_type == pt_type_leaf) {
    
    CArrayAddElementByPointer(ring_pts, CArrayElement(tree_pts, index));
    pt_info->ring_start = ring_pts->count - 1;
    pt_info->ring_end   = ring_pts->count;
    
    pt_info->ring_radius = 0;
    
    float stick_len = pt_dist(tree_pts, index, index - 1);
    
    add_ring_at_index(index - 1, 3, stick_len);
  }
  
  if (pt_info->pt_type == pt_type_child)  add_ring_to_child (index, num_ring_corners, scale);
  
  if (pt_info->pt_type == pt_type_parent) add_ring_to_parent(index);
  
}

static void add_rings() {
  
  CArrayFor(int *, leaf, leaves) {
    add_ring_at_index(*leaf, 0, 0);
  }
  
}

// The output all goes into tree_pts and related global arrays.
static void make_a_tree() {
  
  if (tree_pts == NULL) {
    tree_pts = CArrayNew(0, 3 * sizeof(GLfloat));
  }
  
  if (tree_pt_info == NULL) {
    tree_pt_info = CArrayNew(0, sizeof(Pt_info));
  }
  
  if (leaves == NULL) {
    leaves = CArrayNew(0, sizeof(int));
  }
  
  if (ring_pts == NULL) {
    ring_pts = CArrayNew(0, 3 * sizeof(GLfloat));
  }
  
  vec3  origin    = vec3(0.0);
  vec3  direction = vec3(0.0, 1.0, 0.0);
  float weight    = 1.0;
  float avg_len   = 0.5;
  float min_len   = 0.01;
  int root_index  = -1;
  
  add_to_tree(origin, direction, weight, avg_len, min_len, max_tree_height, root_index);
  
  // TEMP
  if (false) {
    printf("The lines are:\n");
    GLfloat *floats = (GLfloat *)tree_pts->elements;
    for (int i = 0; i < tree_pts->count; i += 2) {
      printf("  (%g, %g, %g) -> ", floats[i * 3],     floats[i * 3 + 1], floats[i * 3 + 2]);
      printf(  "(%g, %g, %g)\n",   floats[i * 3 + 3], floats[i * 3 + 4], floats[i * 3 + 5]);
    }
  }
  
  add_rings();
}

static void draw_ring_at_index(int index) {
  //printf("%s(%d)\n", __func__, index);
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, index);
  glDrawArrays(GL_LINE_LOOP, pt_info->ring_start, pt_info->ring_end - pt_info->ring_start);
  //printf("Just drew a line loop for points [%d,%d).\n", pt_info->ring_start, pt_info->ring_end);
}

static void draw_ring_subtree_at_index(int index) {
  
  draw_ring_at_index(index);
  draw_ring_at_index(index + 1);
  
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, index + 1);
  
  if (pt_info->pt_type == pt_type_parent) {
    draw_ring_subtree_at_index(pt_info->child1);
    draw_ring_subtree_at_index(pt_info->child2);
  }

}

static void use_program(GLuint program, mat4 &mvp, mat3 &normal_matrix) {
  glUseProgram(program);
  
  GLuint mvp_loc = glGetUniformLocation(program, "mvp");
  glUniformMatrix4fv(mvp_loc, 1 /* count */, GL_FALSE /* transpose */, &mvp[0][0]);
  
  GLuint normal_matrix_loc = glGetUniformLocation(program, "normal_matrix");
  glUniformMatrix3fv(normal_matrix_loc, 1 /* count */, GL_FALSE /* transpose */, &normal_matrix[0][0]);
}

static void use_normal_vbo(GLuint normal_vbo) {
  glBindBuffer(GL_ARRAY_BUFFER, normal_vbo);
  set_3f_attrib(2);
}

// The normal points outward from the face with counterclockwise points; the reverse
// bool changes that. This is useful for things like triangle strips.
static vec3 &get_normal_from_last_tri(CArray pt_elts, bool reverse = false) {
  static vec3 normal;
  vec3 pts[3];
  for (int i = 3; i > 0; --i) {
    get_pt(ring_pts, CArrayElementOfType(pt_elts, pt_elts->count - i, GLuint), pts[3 - i]);
  }
  normal = normalize(cross(pts[1] - pts[0], pts[2] - pts[0]));
  if (reverse) normal *= -1;
  return normal;
}

static void setup_stick_bark() {
  
  // Set up the primitive restart index.
  restart_index = ring_pts->count;
  glPrimitiveRestartIndex(restart_index);
  
  stick_bark_pts     = CArrayNew(0,                   sizeof(GLuint));
  stick_bark_normals = CArrayNew(ring_pts->count, 3 * sizeof(GLfloat));
  
  // The stick bark normals will be set instead of added, so initialize it with all-0 data.
  CArrayAddZeroedElements(stick_bark_normals, ring_pts->count);
  
  for (int i = 0; i < tree_pts->count; i += 2) {
    
    if (i) CArrayAddElement(stick_bark_pts, restart_index);
    
    Pt_info *a_info = (Pt_info *)CArrayElement(tree_pt_info, i);
    Pt_info *b_info = (Pt_info *)CArrayElement(tree_pt_info, i + 1);
    
    int start[2] = { a_info->ring_start,      b_info->ring_start };
    int   end[2] = { a_info->ring_end,        b_info->ring_end   };
    int index[2] = { a_info->ring_pt_of_top0, b_info->ring_start };
    
    int num_points = 2 * (end[0] - start[0]) + 2;
    
    int k = 1;
    for (int j = 0; j < num_points; ++j) {
      
      CArrayAddElement(stick_bark_pts, index[k]);
      
      if (j >= 2) {
        bool reverse = (k == 0);  // It's a triangle strip; every other triangle is oriented clockwise.
        vec3 normal = get_normal_from_last_tri(stick_bark_pts, reverse);
        set_pt(stick_bark_normals, index[k], normal);
      }
      
      index[k]++;
      if (index[k] == end[k]) index[k] = start[k];
      k = 1 - k;
      
    }
    
  }
  
  glGenBuffers(1, &stick_bark_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, stick_bark_vbo);
  glBufferData(GL_ARRAY_BUFFER,
               stick_bark_pts->count * stick_bark_pts->elementSize,
               stick_bark_pts->elements,
               GL_STATIC_DRAW);

  
  CArray stick_bark_colors = CArrayNew(0, 3 * sizeof(GLfloat));
  
  for (int i = 0; i < ring_pts->count; ++i) {
    GLfloat rgb[3];
    for (int j = 0; j < 3; ++j) rgb[j] = (float)rand() / RAND_MAX;
    CArrayAddElement(stick_bark_colors, rgb);
  }
  
  GLuint colors_vbo;
  glGenBuffers(1, &colors_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, colors_vbo);
  set_buffer_data(stick_bark_colors);
  set_3f_attrib(1);
    
  glGenBuffers(1, &stick_bark_normal_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, stick_bark_normal_vbo);
  set_buffer_data(stick_bark_normals);
}

#define add_from(x) CArrayAddElementByPointer(joint_bark_pts, CArrayElement(x##_arr, x##_idx % x))

// Inserts values into the joint_bark_pts array.
static void add_triangles_for_joint_bark(CArray m_arr, CArray n_arr) {
  
  if (false) {
    printf("m_arr: ");
    CArrayFor(GLuint *, m_val, m_arr) {
      if ((char *)m_val != m_arr->elements) printf(", ");
      printf("%d", *m_val);
    }
    printf("\n");
    
    printf("n_arr: ");
    CArrayFor(GLuint *, n_val, n_arr) {
      if ((char *)n_val != n_arr->elements) printf(", ");
      printf("%d", *n_val);
    }
    printf("\n");
  }

  
  int m = m_arr->count;
  int n = n_arr->count;
  
  int m_idx = 0;
  int n_idx = 0;
  
  do {
    
    //printf("will add m[%d]\n", m_idx);
    add_from(m);
    //printf("will add n[%d]\n", n_idx);
    add_from(n);
    
    float m_next = (m_idx + 1.0) / m;
    float n_next = (n_idx + 1.0) / n;
    
    if (m_next < n_next) {
      
      m_idx++;
      //printf("will add m[%d]\n", m_idx);
      add_from(m);
      
    } else {
      
      n_idx++;
      //printf("will add n[%d]\n", n_idx);
      add_from(n);
      
    }
    
    vec3 normal = get_normal_from_last_tri(joint_bark_pts);
    GLuint last_index = CArrayElementOfType(joint_bark_pts, joint_bark_pts->count - 1, GLuint);
    set_pt(joint_bark_normals, last_index, normal);
    
  } while (m_idx < m || n_idx < n);
  
  if (false) {
    printf("Triangles:\n");
    int i = 0;
    CArrayFor(GLuint *, pt, joint_bark_pts) {
      printf("%s", i % 3 ? ", " : "  ");
      printf("%d", *pt);
      if (i % 3 == 2) printf("\n");
      i++;
    }
    printf("\n");
  }
}

static bool pt_is_leaf(int index) {
  Pt_info *pt_info = (Pt_info *)CArrayElement(tree_pt_info, index);
  return pt_info->pt_type == pt_type_leaf;
}

static void setup_subtree_joint_bark(int parent_index) {
  
  Pt_info *parent_info = (Pt_info *)CArrayElement(tree_pt_info, parent_index);
  int kids[2] = { parent_info->child1, parent_info->child2 };
  Pt_info *child_info[2];
  for (int i = 0; i < 2; ++i) {
    child_info[i] = (Pt_info *)CArrayElement(tree_pt_info, kids[i]);
  }
  
  CArray top    = CArrayNew(0, sizeof(GLuint));
  CArray bottom = CArrayNew(0, sizeof(GLuint));
  
  for (int r_index = parent_info->ring_start; r_index < parent_info->ring_end; ++r_index) {
    CArrayAddElement(bottom, r_index);
  }
  
  for (int i = 0; i < 2; ++i) {
    for (int r_index = child_info[i]->ring_start + 1; r_index < child_info[i]->ring_end; ++r_index) {
      CArrayAddElement(top, r_index);
    }
  }
  
  add_triangles_for_joint_bark(top, bottom);
  
  CArrayDelete(top);
  CArrayDelete(bottom);
  
  
  for (int i = 0; i < 2; ++i) {
    if (!pt_is_leaf(kids[i] + 1)) {
      setup_subtree_joint_bark(kids[i] + 1);
    }
  }
}

// For now we'll reuse the random colors from setup_stick_bark. This should
// work fine, but will result in some adjacent triangles of the same color.
static void setup_joint_bark() {
  
  joint_bark_pts     = CArrayNew(0,                   sizeof(GLuint));
  joint_bark_normals = CArrayNew(ring_pts->count, 3 * sizeof(GLfloat));
  
  // The normals will be set instead of added, so we premark the space as used.
  joint_bark_normals->count = ring_pts->count;
  
  setup_subtree_joint_bark(1);
  
  glGenBuffers(1, &joint_bark_vbo);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, joint_bark_vbo);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER,
               joint_bark_pts->count * joint_bark_pts->elementSize,
               joint_bark_pts->elements,
               GL_STATIC_DRAW);
  
  glGenBuffers(1, &joint_bark_normal_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, joint_bark_normal_vbo);
  set_buffer_data(joint_bark_normals);
}


// Public functions.

extern "C" {
  
  void render__init() {
    glClearColor(0, 0.3, 0.1, 1.0);
    
    glEnable(GL_CULL_FACE);
    
    line_program = glhelp__load_program("line_vs.glsl", "line_fs.glsl");
    bark_program = glhelp__load_program("bark_vs.glsl", "bark_fs.glsl");
    
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    
    make_a_tree();
    GLsizeiptr    data_size = tree_pts->count * tree_pts->elementSize;
    const GLvoid *data      = tree_pts->elements;
    num_pts                 = tree_pts->count;

    if (false) {
      data = get_vertices(&data_size, &num_pts);
    }
    
    glBufferData(GL_ARRAY_BUFFER, data_size, data, GL_STATIC_DRAW);
    
    glVertexAttribPointer(0,             // location
                          3,             // num coords
                          GL_FLOAT,      // coord type
                          GL_FALSE,      // normalize
                          0,             // stride
                          (void *)(0));  // offset
    glEnableVertexAttribArray(0);  // 0 is the location to enable
        
    model = translate(mat4(1), vec3(0, -1, 0));
    model = scale(model, vec3(3));
    
    //model = mat4(1.0);  // The identity matrix.
    view  = lookAt(vec3(4.0, 4.0, 2.0), vec3(0.0), vec3(0.0, 1.0, 0.0));
    
    printf("num_pts=%d\n", num_pts);
    
    if (false) {
      printf("branch_pt triples:\n");
      int i = 0;
      CArrayFor(int *, tree_pt_idx, branch_pts) {
        if (i % 3 == 0) printf("  (");
        printf("%d", *tree_pt_idx);
        printf("%s", i % 3 == 2 ? ")\n" : ", ");
        ++i;
      }
    }
    
    if (false) {
      
      // Print the data in tree_pt_info.
      const char *type_str[] = { "leaf", "parent", "child " };
      printf("tree_pt_info:\n");
      int i = 0;
      CArrayFor(Pt_info *, pt_info, tree_pt_info) {
        printf("  %d: ", i);
        printf("%s", type_str[pt_info->pt_type]);
        if (pt_info->pt_type == pt_type_parent) {
          printf(" with children %d, %d", pt_info->child1, pt_info->child2);
        } else if (pt_info->pt_type == pt_type_child) {
          printf(" with parent %d", pt_info->parent);
        }
        printf(" ring=[%d,%d)\n", pt_info->ring_start, pt_info->ring_end);
        ++i;
      }
      
    }
    
    if (false) {
      
      // Print out the leaves.
      printf("leaves:\n  ");
      CArrayFor(int *, leaf, leaves) {
        if ((char *)leaf != leaves->elements) printf(", ");
        printf("%d", *leaf);
      }
      printf("\n");
    }
    
    glGenVertexArrays(1, &rings_vao);
    glBindVertexArray(rings_vao);
    
    GLuint rings_vbo;
    glGenBuffers(1, &rings_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, rings_vbo);
    glBufferData(GL_ARRAY_BUFFER, ring_pts->count * ring_pts->elementSize, ring_pts->elements, GL_STATIC_DRAW);
    glVertexAttribPointer(0,             // location
                          3,             // num coords
                          GL_FLOAT,      // coord type
                          GL_FALSE,      // normalize
                          0,             // stride
                          (void *)(0));  // offset
    glEnableVertexAttribArray(0);  // 0 is the location.
    
    if (do_draw_stick_lines) {
    
      // This will continue to use the rings_vao.
      
      num_stick_line_elts = tree_pts->count;
      size_t stick_line_buffer_size = sizeof(GLuint) * num_stick_line_elts;
      GLuint *stick_line_indexes = (GLuint *)malloc(stick_line_buffer_size);
      stick_line_elts = stick_line_indexes;
      
      for (GLuint i = 0; i < tree_pts->count; i += 2) {
        
        Pt_info *pt_info;
        
        pt_info = (Pt_info *)CArrayElement(tree_pt_info, i);
        stick_line_indexes[i]     = pt_info->ring_pt_of_top0;
        
        pt_info = (Pt_info *)CArrayElement(tree_pt_info, i + 1);
        stick_line_indexes[i + 1] = pt_info->ring_start;
        
        if (i < 10) {
          printf("Added indexes: %d, %d\n", stick_line_indexes[i], stick_line_indexes[i + 1]);
        }
        
      }
      
      glGenBuffers(1, &stick_lines_vbo);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, stick_lines_vbo);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, stick_line_buffer_size, stick_line_indexes, GL_STATIC_DRAW);
      
      printf("Added %zd bytes into the GL_ELEMENT_ARRAY_BUFFER.\n", stick_line_buffer_size);
      
    }
    
    setup_stick_bark();
    setup_joint_bark();
    
    if (false) {
      
      printf("First few stick bark normal vectors are:\n");
      for (int i = 0; i < 10; ++i) {
        
        vec3 v;
        get_pt(stick_bark_normals, i, v);
        printf("  %s\n", vec_str(v));
        
      }
      
    }
    
    // TEMP TODO Cleanup. This is test code to make sure I can
    // run Lua from C.
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    char *filepath = file__get_path("test.lua");
    luaL_dofile(L, filepath);
    
  }  // render__init
  
  void render__draw(int w, int h) {
    
    static float angle = 0.0;
    angle += 0.01;  // (2 * M_PI / 360.0);
    
    glViewport(0, 0, w, h);
    
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    GLfloat aspect_ratio = (GLfloat)w / h;
    mat4 projection = perspective(45.0f, aspect_ratio, 0.1f, 1000.0f);
    
    model = rotate(mat4(1.0), angle, vec3(0.0, 1.0, 0.0));
    model = translate(model, vec3(0, -3, 0));
    model = scale(model, vec3(zoom_scale));
    
    mat4 mvp = projection * view * model;
    mat3 normal_matrix = mat3(view * model);
    
    if (do_draw_skeleton) {

      use_program(line_program, mvp, normal_matrix);
      glBindVertexArray(vao);
      glDrawArrays(GL_LINES, 0, num_pts);
      
    }
    
    if (do_draw_rings || do_draw_stick_lines) {
      
      use_program(line_program, mvp, normal_matrix);
      glBindVertexArray(rings_vao);
      
      if (do_draw_rings) draw_ring_subtree_at_index(0);
      
      if (do_draw_stick_lines) {
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, stick_lines_vbo);
        glDrawElements(GL_LINES, num_stick_line_elts, GL_UNSIGNED_INT, NULL);
      }
    }
    
    if (do_draw_stick_bark) {
      
      use_program(bark_program, mvp, normal_matrix);
      use_normal_vbo(stick_bark_normal_vbo);
      
      glEnable(GL_DEPTH_TEST);
      
      glEnable(GL_PRIMITIVE_RESTART);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, stick_bark_vbo);
      glDrawElements(GL_TRIANGLE_STRIP, stick_bark_pts->count, GL_UNSIGNED_INT, NULL);
      glDisable(GL_PRIMITIVE_RESTART);
      
    }
    
    if (do_draw_joint_bark) {
      
      use_program(bark_program, mvp, normal_matrix);
      use_normal_vbo(joint_bark_normal_vbo);
      
      glEnable(GL_DEPTH_TEST);
      
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, joint_bark_vbo);
      glDrawElements(GL_TRIANGLES, joint_bark_pts->count, GL_UNSIGNED_INT, NULL);
      
    }
    
  }
  
  void render__mouse_moved(int x, int y, double dx, double dy) {
    
  }
  
  void render__mouse_down(int x, int y) {
    
  }
  
}

