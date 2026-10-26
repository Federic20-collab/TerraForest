// SPDX-License-Identifier: 0BSD
#include "camera.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
namespace {
constexpr double camera_distance=7.2;
constexpr double camera_height=3.0;
constexpr double anchor_height=.65;
constexpr double camera_clearance=1.1;
constexpr double terrain_probe=24.0;
}
void NativeVehicleCamera::_bind_methods(){ClassDB::bind_method(D_METHOD("update","body","camera","delta"),&NativeVehicleCamera::update);}
NativeVehicleCamera::NativeVehicleCamera(){
    shape.instantiate();shape->set_radius(.25);
    query.instantiate();query->set_shape(shape);query->set_margin(.05);query->set_collision_mask(7);
}
bool NativeVehicleCamera::update(RigidBody3D *body,Camera3D *camera,double delta){
    if(!body||!camera||!body->is_inside_tree()||!camera->is_inside_tree()||!std::isfinite(delta)||delta<=0)return false;
    auto world=body->get_world_3d();if(world.is_null()||world!=camera->get_world_3d())return false;
    auto *space=world->get_direct_space_state();if(!space)return false;
    Vector3 at=body->get_global_position(),current=camera->get_global_position();
    if(!at.is_finite()||!current.is_finite())return false;
    Vector3 target_forward=body->get_global_transform().basis.get_column(2);target_forward.y=0;
    target_forward=target_forward.length_squared()<.0001?Vector3(0,0,1):target_forward.normalized();
    if(!initialized){
        smoothed_forward=target_forward;
        initialized=true;
    }else{
        double turn_alpha=1-std::exp(-8.0*std::min(delta,.1));
        smoothed_forward=smoothed_forward.slerp(target_forward,real_t(turn_alpha));
        if(smoothed_forward.length_squared()<.0001)smoothed_forward=target_forward;
        else smoothed_forward=smoothed_forward.normalized();
    }
    Vector3 anchor=at+Vector3(0,anchor_height,0);
    Vector3 desired=at-smoothed_forward*camera_distance+Vector3(0,camera_height,0);
    TypedArray<RID> excluded;excluded.push_back(body->get_rid());
    // Terrain behind a descending vehicle can be higher than the boom. Lift the
    // target above the ground under its own X/Z before sweeping the camera.
    auto ground_ray=PhysicsRayQueryParameters3D::create(
        desired+Vector3(0,terrain_probe,0),
        desired-Vector3(0,terrain_probe,0),
        1,
        excluded);
    Dictionary ground_hit=space->intersect_ray(ground_ray);
    if(!ground_hit.is_empty()){
        Vector3 ground=ground_hit["position"];
        desired.y=std::max<float>(desired.y,float(ground.y)+float(camera_clearance));
    }
    query->set_exclude(excluded);
    bool anchor_clear=false;
    for(double lift: {0.0,1.8,3.8,6.0}){
        anchor=at+Vector3(0,anchor_height+lift,0);
        query->set_transform(Transform3D(Basis(),anchor));query->set_motion(Vector3());
        if(space->intersect_shape(query,1).is_empty()){anchor_clear=true;break;}
    }
    if(!anchor_clear){
        // Never freeze inside a slope. A high overhead pose is degraded, but it
        // keeps the vehicle visible and lets the next frame recover.
        camera->set_global_position(at+Vector3(0,8,0));
        camera->look_at(at+Vector3(0,1,0),Vector3(0,1,0));
        return true;
    }
    query->set_transform(Transform3D(Basis(),current));query->set_motion(Vector3());
    bool current_embedded=!space->intersect_shape(query,1).is_empty();
    auto current_ground_ray=PhysicsRayQueryParameters3D::create(
        current+Vector3(0,terrain_probe,0),
        current-Vector3(0,terrain_probe,0),
        1,
        excluded);
    Dictionary current_ground_hit=space->intersect_ray(current_ground_ray);
    bool current_below_terrain=false;
    if(!current_ground_hit.is_empty()){
        Vector3 current_ground=current_ground_hit["position"];
        current_below_terrain=current.y<current_ground.y+.3f;
    }
    // A restored or hillside camera can be far from the vehicle or below the
    // terrain. Snap once instead of letting the old pose drag the first frames.
    bool snap=current_embedded||current_below_terrain||current.distance_squared_to(desired)>900.0;
    Vector3 candidate=snap?desired:current.lerp(desired,real_t(1-std::exp(-7.5*std::min(delta,.1))));
    Vector3 motion=candidate-anchor;
    query->set_transform(Transform3D(Basis(),anchor));query->set_motion(motion);
    PackedFloat32Array fractions=space->cast_motion(query);
    if(fractions.size()!=2||!std::isfinite(fractions[0])){
        camera->set_global_position(at+Vector3(0,7,0));
        camera->look_at(at+Vector3(0,1,0),Vector3(0,1,0));
        return true;
    }
    float fraction=std::clamp(fractions[0],0.f,1.f);
    Vector3 position=anchor+motion*fraction;
    if(fraction<.2f)position=at+Vector3(0,7,0);
    camera->set_global_position(position);
    Vector3 look=at+Vector3(0,.9,0)+smoothed_forward*1.0;
    if(position.distance_squared_to(look)>.0001)camera->look_at(look,Vector3(0,1,0));
    return true;
}
}
