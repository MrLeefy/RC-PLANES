#pragma once

#include "rcbeam/solver.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class RCBeamSolver : public RefCounted {
    GDCLASS(RCBeamSolver, RefCounted)

public:
    enum MaterialPreset {
        MATERIAL_EPO_FOAM = 0,
        MATERIAL_BALSA = 1,
        MATERIAL_PLYWOOD = 2,
        MATERIAL_CARBON_FIBER = 3,
        MATERIAL_ALUMINUM = 4,
        MATERIAL_STEEL_WIRE = 5,
        MATERIAL_GENERIC_COMPOSITE = 6,
    };

    RCBeamSolver() = default;

    void configure(
        int normal_substeps,
        int impact_substeps,
        int max_substeps,
        double impact_hold_seconds,
        double impact_trigger
    );

    void reserve(int node_capacity, int beam_capacity);
    void clear();

    int add_node(Vector3 position, double mass_kg, bool pinned = false);
    int add_beam_preset(int a, int b, int material_preset, int break_group = 0);
    int add_beam_custom(
        int a,
        int b,
        double stiffness_n_per_m,
        double damping_ns_per_m,
        double yield_tension,
        double yield_compression,
        double break_tension,
        double break_compression,
        double plasticity_rate,
        double max_plastic_strain,
        int break_group = 0
    );

    void apply_force(int node, Vector3 force_n);
    void apply_impulse(int node, Vector3 impulse_ns);
    void apply_radial_impulse(Vector3 center, Vector3 impulse_ns, double radius_m);
    void notify_impact(double normalized_severity);

    Dictionary step(double dt_seconds, Vector3 external_acceleration_mps2 = Vector3(0.0, -9.81, 0.0));

    PackedVector3Array get_node_positions() const;
    PackedVector3Array get_node_velocities() const;
    PackedFloat32Array get_beam_state() const;
    PackedInt32Array consume_break_events();

    int get_node_count() const;
    int get_beam_count() const;

protected:
    static void _bind_methods();

private:
    rcbeam::SolverConfig config_{};
    rcbeam::Solver solver_{config_};

    static rcbeam::Vec3 to_native(Vector3 value);
    static Vector3 to_godot(const rcbeam::Vec3& value);
    static rcbeam::MaterialKind to_material_kind(int preset);
};

} // namespace godot
