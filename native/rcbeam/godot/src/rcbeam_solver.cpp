#include "rcbeam_solver.hpp"

#include <algorithm>

#include <godot_cpp/core/class_db.hpp>

namespace godot {

rcbeam::Vec3 RCBeamSolver::to_native(Vector3 value) {
    return {
        static_cast<float>(value.x),
        static_cast<float>(value.y),
        static_cast<float>(value.z),
    };
}

Vector3 RCBeamSolver::to_godot(const rcbeam::Vec3& value) {
    return Vector3(value.x, value.y, value.z);
}

rcbeam::MaterialKind RCBeamSolver::to_material_kind(int preset) {
    const int clamped = std::clamp(
        preset,
        static_cast<int>(MATERIAL_EPO_FOAM),
        static_cast<int>(MATERIAL_GENERIC_COMPOSITE)
    );
    return static_cast<rcbeam::MaterialKind>(clamped);
}

void RCBeamSolver::configure(
    int normal_substeps,
    int impact_substeps,
    int max_substeps,
    double impact_hold_seconds,
    double impact_trigger
) {
    config_.normal_substeps = static_cast<std::uint32_t>(std::max(normal_substeps, 1));
    config_.impact_substeps = static_cast<std::uint32_t>(std::max(impact_substeps, normal_substeps));
    config_.max_substeps = static_cast<std::uint32_t>(std::max(max_substeps, impact_substeps));
    config_.impact_hold_seconds = static_cast<float>(std::max(impact_hold_seconds, 0.0));
    config_.impact_trigger = static_cast<float>(std::clamp(impact_trigger, 0.0, 1.0));
    solver_ = rcbeam::Solver(config_);
}

void RCBeamSolver::reserve(int node_capacity, int beam_capacity) {
    solver_.reserve(
        static_cast<std::size_t>(std::max(node_capacity, 0)),
        static_cast<std::size_t>(std::max(beam_capacity, 0))
    );
}

void RCBeamSolver::clear() {
    solver_.clear();
}

int RCBeamSolver::add_node(Vector3 position, double mass_kg, bool pinned) {
    return static_cast<int>(solver_.add_node(to_native(position), static_cast<float>(mass_kg), pinned));
}

int RCBeamSolver::add_beam_preset(int a, int b, int material_preset, int break_group) {
    const rcbeam::Material material = rcbeam::material_preset(to_material_kind(material_preset));
    return static_cast<int>(solver_.add_beam(
        static_cast<std::uint32_t>(a),
        static_cast<std::uint32_t>(b),
        material,
        static_cast<std::uint16_t>(std::clamp(break_group, 0, 65535))
    ));
}

int RCBeamSolver::add_beam_custom(
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
    int break_group
) {
    rcbeam::Material material{};
    material.stiffness_n_per_m = static_cast<float>(std::max(stiffness_n_per_m, 0.0));
    material.damping_ns_per_m = static_cast<float>(std::max(damping_ns_per_m, 0.0));
    material.yield_tension = static_cast<float>(std::max(yield_tension, 0.0));
    material.yield_compression = static_cast<float>(std::max(yield_compression, 0.0));
    material.break_tension = static_cast<float>(std::max(break_tension, yield_tension));
    material.break_compression = static_cast<float>(std::max(break_compression, yield_compression));
    material.plasticity_rate = static_cast<float>(std::max(plasticity_rate, 0.0));
    material.max_plastic_strain = static_cast<float>(std::max(max_plastic_strain, 0.0));

    return static_cast<int>(solver_.add_beam(
        static_cast<std::uint32_t>(a),
        static_cast<std::uint32_t>(b),
        material,
        static_cast<std::uint16_t>(std::clamp(break_group, 0, 65535))
    ));
}

void RCBeamSolver::apply_force(int node, Vector3 force_n) {
    if (node < 0) {
        return;
    }
    solver_.apply_force(static_cast<std::uint32_t>(node), to_native(force_n));
}

void RCBeamSolver::apply_impulse(int node, Vector3 impulse_ns) {
    if (node < 0) {
        return;
    }
    solver_.apply_impulse(static_cast<std::uint32_t>(node), to_native(impulse_ns));
}

void RCBeamSolver::apply_radial_impulse(Vector3 center, Vector3 impulse_ns, double radius_m) {
    solver_.apply_radial_impulse(to_native(center), to_native(impulse_ns), static_cast<float>(radius_m));
}

void RCBeamSolver::notify_impact(double normalized_severity) {
    solver_.notify_impact(static_cast<float>(normalized_severity));
}

Dictionary RCBeamSolver::step(double dt_seconds, Vector3 external_acceleration_mps2) {
    const rcbeam::StepStats stats = solver_.step(
        static_cast<float>(dt_seconds),
        to_native(external_acceleration_mps2)
    );

    Dictionary out;
    out["substeps"] = static_cast<int64_t>(stats.substeps);
    out["active_beams"] = static_cast<int64_t>(stats.active_beams);
    out["newly_broken_beams"] = static_cast<int64_t>(stats.newly_broken_beams);
    out["max_abs_strain"] = stats.max_abs_strain;
    out["max_node_speed_mps"] = stats.max_node_speed_mps;
    return out;
}

PackedVector3Array RCBeamSolver::get_node_positions() const {
    PackedVector3Array out;
    out.resize(static_cast<int64_t>(solver_.nodes().size()));
    for (std::size_t i = 0; i < solver_.nodes().size(); ++i) {
        out.set(static_cast<int64_t>(i), to_godot(solver_.nodes()[i].position));
    }
    return out;
}

PackedVector3Array RCBeamSolver::get_node_velocities() const {
    PackedVector3Array out;
    out.resize(static_cast<int64_t>(solver_.nodes().size()));
    for (std::size_t i = 0; i < solver_.nodes().size(); ++i) {
        out.set(static_cast<int64_t>(i), to_godot(solver_.nodes()[i].velocity));
    }
    return out;
}

PackedFloat32Array RCBeamSolver::get_beam_state() const {
    // Four floats per beam: strain, force N, rest length m, broken flag.
    PackedFloat32Array out;
    out.resize(static_cast<int64_t>(solver_.beams().size() * 4));
    for (std::size_t i = 0; i < solver_.beams().size(); ++i) {
        const rcbeam::Beam& beam = solver_.beams()[i];
        const int64_t base = static_cast<int64_t>(i * 4);
        out.set(base + 0, beam.last_strain);
        out.set(base + 1, beam.last_force_n);
        out.set(base + 2, beam.rest_length);
        out.set(base + 3, beam.broken ? 1.0f : 0.0f);
    }
    return out;
}

PackedInt32Array RCBeamSolver::consume_break_events() {
    const std::vector<std::uint32_t> events = solver_.consume_break_events();
    PackedInt32Array out;
    out.resize(static_cast<int64_t>(events.size()));
    for (std::size_t i = 0; i < events.size(); ++i) {
        out.set(static_cast<int64_t>(i), static_cast<int32_t>(events[i]));
    }
    return out;
}

int RCBeamSolver::get_node_count() const {
    return static_cast<int>(solver_.nodes().size());
}

int RCBeamSolver::get_beam_count() const {
    return static_cast<int>(solver_.beams().size());
}

void RCBeamSolver::_bind_methods() {
    ClassDB::bind_method(D_METHOD(
        "configure",
        "normal_substeps",
        "impact_substeps",
        "max_substeps",
        "impact_hold_seconds",
        "impact_trigger"
    ), &RCBeamSolver::configure);

    ClassDB::bind_method(D_METHOD("reserve", "node_capacity", "beam_capacity"), &RCBeamSolver::reserve);
    ClassDB::bind_method(D_METHOD("clear"), &RCBeamSolver::clear);
    ClassDB::bind_method(D_METHOD("add_node", "position", "mass_kg", "pinned"), &RCBeamSolver::add_node, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("add_beam_preset", "a", "b", "material_preset", "break_group"), &RCBeamSolver::add_beam_preset, DEFVAL(0));
    ClassDB::bind_method(D_METHOD(
        "add_beam_custom",
        "a", "b",
        "stiffness_n_per_m", "damping_ns_per_m",
        "yield_tension", "yield_compression",
        "break_tension", "break_compression",
        "plasticity_rate", "max_plastic_strain",
        "break_group"
    ), &RCBeamSolver::add_beam_custom, DEFVAL(0));

    ClassDB::bind_method(D_METHOD("apply_force", "node", "force_n"), &RCBeamSolver::apply_force);
    ClassDB::bind_method(D_METHOD("apply_impulse", "node", "impulse_ns"), &RCBeamSolver::apply_impulse);
    ClassDB::bind_method(D_METHOD("apply_radial_impulse", "center", "impulse_ns", "radius_m"), &RCBeamSolver::apply_radial_impulse);
    ClassDB::bind_method(D_METHOD("notify_impact", "normalized_severity"), &RCBeamSolver::notify_impact);
    ClassDB::bind_method(D_METHOD("step", "dt_seconds", "external_acceleration_mps2"), &RCBeamSolver::step, DEFVAL(Vector3(0.0, -9.81, 0.0)));

    ClassDB::bind_method(D_METHOD("get_node_positions"), &RCBeamSolver::get_node_positions);
    ClassDB::bind_method(D_METHOD("get_node_velocities"), &RCBeamSolver::get_node_velocities);
    ClassDB::bind_method(D_METHOD("get_beam_state"), &RCBeamSolver::get_beam_state);
    ClassDB::bind_method(D_METHOD("consume_break_events"), &RCBeamSolver::consume_break_events);
    ClassDB::bind_method(D_METHOD("get_node_count"), &RCBeamSolver::get_node_count);
    ClassDB::bind_method(D_METHOD("get_beam_count"), &RCBeamSolver::get_beam_count);

    BIND_ENUM_CONSTANT(MATERIAL_EPO_FOAM);
    BIND_ENUM_CONSTANT(MATERIAL_BALSA);
    BIND_ENUM_CONSTANT(MATERIAL_PLYWOOD);
    BIND_ENUM_CONSTANT(MATERIAL_CARBON_FIBER);
    BIND_ENUM_CONSTANT(MATERIAL_ALUMINUM);
    BIND_ENUM_CONSTANT(MATERIAL_STEEL_WIRE);
    BIND_ENUM_CONSTANT(MATERIAL_GENERIC_COMPOSITE);
}

} // namespace godot
