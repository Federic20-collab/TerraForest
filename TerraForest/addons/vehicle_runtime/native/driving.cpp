// SPDX-License-Identifier: 0BSD
// Port of the user's Vehicle Driving Test steering and longitudinal policy.
#include "driving.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
namespace {
constexpr double radians=0.017453292519943295;
constexpr double low_speed_max_steer=30*radians;
constexpr double lateral_accel_limit=20.0;
constexpr double steer_input_apply=5.5;
constexpr double steer_input_release=6.0;
constexpr double steer_input_reverse=5.75;
constexpr double steer_cap_recovery=12.0*radians;
constexpr double total_grip_accel=20.0;
constexpr double max_yaw_rate=85*radians;
constexpr double handbrake_hold_speed=1.0;
constexpr double handbrake_force=22000.0;
constexpr double handbrake_damping=3.0;
double toward(double a,double b,double step){return a+std::clamp(b-a,-step,step);}
double sign(double x){return x>0?1:(x<0?-1:0);}
bool zero(double x){return std::abs(x)<0.00001;}
Vector3 forward(RigidBody3D *body,Vector3 up){
    Vector3 value=body->get_global_transform().basis.get_column(2).slide(up);
    return value.length_squared()<.0001?Vector3(0,0,1):value.normalized();
}
}
void NativeDrivingPolicy::_bind_methods(){
    ClassDB::bind_method(D_METHOD("travel_bounds","position","velocity","delta"),&NativeDrivingPolicy::travel_bounds);
    ClassDB::bind_method(D_METHOD("reset"),&NativeDrivingPolicy::reset);
    ClassDB::bind_method(D_METHOD("steering","input","speed","delta"),&NativeDrivingPolicy::steering);
    ClassDB::bind_method(D_METHOD("speed","previous","throttle","reverse_brake","parked","boost","delta"),&NativeDrivingPolicy::speed);
    ClassDB::bind_method(D_METHOD("apply_grounded","body","up","speed"),&NativeDrivingPolicy::apply_grounded);
    ClassDB::bind_method(D_METHOD("apply_free","body","up","throttle","reverse_brake","handbrake","parked","supported"),&NativeDrivingPolicy::apply_free);
    ClassDB::bind_method(D_METHOD("stabilize","body","up","supported","loaded_wheels"),&NativeDrivingPolicy::stabilize);
}
AABB NativeDrivingPolicy::travel_bounds(Vector3 position,Vector3 velocity,double delta) const {
    if(!position.is_finite()||!velocity.is_finite()||!std::isfinite(delta)||delta<=0||delta>.1)return AABB(Vector3(INFINITY,INFINITY,INFINITY),Vector3());
    // Supplied chassis and suspension fit within a 3 m sphere. An isotropic
    // motion allowance also covers steering changes during the next tick.
    double radius=3.25+velocity.length()*delta+30*delta*delta;
    Vector3 extent{real_t(radius),real_t(radius),real_t(radius)};
    return AABB(position-extent,extent*2);
}
void NativeDrivingPolicy::reset(){fraction_=angle_=sign_=0;cap_=low_speed_max_steer;}
double NativeDrivingPolicy::apply_grounded(RigidBody3D *body,Vector3 up,double speed) const {
    if(!body||!body->is_inside_tree()||!up.is_finite()||up.length_squared()<.0001||!std::isfinite(speed))return 0;
    up.normalize();Vector3 f=forward(body,up),side=up.cross(f);
    side=side.length_squared()<.0001?Vector3(1,0,0):side.normalized();
    double yaw=std::clamp(speed*std::tan(angle_)/2.726,-max_yaw_rate,max_yaw_rate);
    Vector3 linear=body->get_linear_velocity(),angular=body->get_angular_velocity();
    body->set_linear_velocity(f*real_t(speed)+side*real_t(yaw*1.2581)+up*linear.dot(up));
    body->set_angular_velocity(angular-up*angular.dot(up)+up*real_t(yaw));
    return yaw;
}
void NativeDrivingPolicy::apply_free(RigidBody3D *body,Vector3 up,double throttle,double reverse_brake,bool handbrake,bool parked,bool supported) const {
    if(!supported||!body||!body->is_inside_tree()||!up.is_finite()||up.length_squared()<.0001||!std::isfinite(throttle)||!std::isfinite(reverse_brake))return;
    up.normalize();Vector3 f=forward(body,up),v=body->get_linear_velocity();double longitudinal=v.dot(f);
    if(parked){if(v.length()>.1)body->apply_central_force(-v.normalized()*22000);return;}
    if(throttle>0&&reverse_brake>0){if(v.length()>.1)body->apply_central_force(-v.normalized()*22000);}
    else if(throttle>0){if(longitudinal<60)body->apply_central_force(f*real_t(12000*throttle));}
    else if(reverse_brake>0){
        if(longitudinal>1)body->apply_central_force(-f*real_t(22000*reverse_brake));
        else if(longitudinal>-15)body->apply_central_force(-f*real_t(7000*reverse_brake));
    }
    if(handbrake){
        // A parking brake must hold the mass against the downhill gravity
        // component, not merely push against the current horizontal velocity.
        // The force below cancels that component; low-speed tangential motion is
        // removed so the vehicle does not creep when Space is held on terrain.
        Vector3 gravity=body->get_gravity();
        Vector3 gravity_tangent=gravity-up*gravity.dot(up);
        body->apply_central_force(-gravity_tangent*real_t(body->get_mass()));
        Vector3 planar=v-up*v.dot(up);
        double planar_speed=planar.length();
        if(planar_speed>handbrake_hold_speed){
            body->apply_central_force(-planar.normalized()*real_t(handbrake_force));
            body->apply_central_force(-planar*real_t(body->get_mass()*handbrake_damping));
        }else{
            body->set_linear_velocity(up*real_t(v.dot(up)));
            body->set_angular_velocity(Vector3());
        }
    }
}
double NativeDrivingPolicy::stabilize(RigidBody3D *body,Vector3 up,bool supported,int loaded_wheels) const {
    if(!body||!body->is_inside_tree()||!up.is_finite()||up.length_squared()<.0001)return 0;
    up.normalize();double roll=0;
    if(supported){
        auto basis=body->get_global_transform().basis;Vector3 side=basis.get_column(0).normalized(),f=basis.get_column(2).normalized(),angular=body->get_angular_velocity();
        double re=std::clamp(double(side.dot(up)),-1.0,1.0),pe=std::clamp(double(f.dot(up)),-1.0,1.0);
        roll=std::asin(re)/radians;
        double rt=std::clamp(-re*5200-angular.dot(f)*2500,-5200.0,5200.0);
        double pt=std::clamp(pe*1100-angular.dot(side)*1300,-2300.0,2300.0);
        body->apply_torque((f*real_t(rt)+side*real_t(pt)).slide(up));
    }
    Vector3 v=body->get_linear_velocity();v.y=0;double planar=v.length();
    if(loaded_wheels>=3&&planar>3)body->apply_central_force(Vector3(0,real_t(-std::min(planar*planar*.55,1450.0)),0));
    return roll;
}
Vector3 NativeDrivingPolicy::steering(double input,double speed,double delta){
    if(!std::isfinite(input)||!std::isfinite(speed)||!std::isfinite(delta)||delta<=0||delta>0.1)return Vector3(angle_,cap_,fraction_);
    input=std::clamp(input,-1.0,1.0);speed=std::abs(speed);
    double instantaneous=speed<1?low_speed_max_steer:std::min(low_speed_max_steer,std::atan(lateral_accel_limit*2.726/std::max(speed*speed,1.0)));
    double input_sign=sign(input);
    if(zero(input)){sign_=0;cap_=instantaneous;}
    else if(zero(sign_)||input_sign!=sign_){sign_=input_sign;cap_=instantaneous;}
    else if(instantaneous<cap_)cap_=instantaneous;
    else cap_=toward(cap_,instantaneous,steer_cap_recovery*delta);
    double rate=zero(input)?steer_input_release:(!zero(fraction_)&&sign(fraction_)!=input_sign?steer_input_reverse:steer_input_apply);
    fraction_=toward(fraction_,input,rate*delta);
    angle_=toward(angle_,fraction_*cap_,120*radians*delta);
    if(std::abs(angle_)<0.00005)angle_=0;
    return Vector3(angle_,cap_,fraction_);
}
Vector2 NativeDrivingPolicy::speed(double previous,double throttle,double reverse_brake,bool parked,double boost,double delta) const {
    if(!std::isfinite(previous)||!std::isfinite(throttle)||!std::isfinite(reverse_brake)||!std::isfinite(boost)||!std::isfinite(delta)||delta<=0||delta>0.1)return Vector2(std::isfinite(previous)?previous:0,0);
    boost=std::clamp(boost,0.0,1.0);double v=previous,acceleration=0,limit=55+17*boost;
    if(parked)return Vector2(toward(v,0,18*delta),0);
    if(throttle>0&&reverse_brake>0)return Vector2(toward(v,0,14*delta),0);
    if(throttle>0){
        if(v<-.4)v=toward(v,0,14*delta);
        else {
            double ratio=std::clamp(std::max(v,0.0)/std::max(limit,.001),0.0,1.0);
            acceleration=(8.8+(1.7-8.8)*ratio)*(1-ratio)*(1+.42*boost);
            double lateral=v*v*std::abs(std::tan(angle_)/2.726);
            acceleration=std::min(acceleration,std::sqrt(std::max(total_grip_accel*total_grip_accel-lateral*lateral,0.0)));
            v=std::min(v+acceleration*delta,limit);
        }
    } else if(reverse_brake>0){
        if(v>.4)v=toward(v,0,14*delta);
        else {double ratio=std::clamp(std::abs(v)/15,0.0,1.0);acceleration=-5.8*(1-ratio);v=std::max(v+acceleration*delta,-15.0);}
    } else v=toward(v,0,1.45*delta);
    return Vector2(v,acceleration);
}
}
