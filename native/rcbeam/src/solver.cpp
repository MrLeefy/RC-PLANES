#include "rcbeam/solver.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace rcbeam {

namespace {

constexpr float kEpsilon = 1.0e-6f;

float clampf(float v, float lo, float hi) {
    return std::max(lo, std::min(v, hi));
}

Vec3 clamp_speed(Vec3 v, float max_speed) {
    const float lsq = length_squared(v);
    const float max_sq = max_speed * max_speed;
    if (lsq <= max_sq || lsq <= kEpsilon) {
        return v;
    }
    return v * (max_speed / std::sqrt(lsq));
}

} // namespace

Vec3& Vec3::operator+=(const Vec3& rhs) {
    x += rhs.x;
    y += rhs.y;
    z += rhs.z;
    return *this;
}

Vec3& Vec3::operator-=(const Vec3& rhs) {
    x -= rhs.x;
    y -= rhs.y;
    z -= rhs.z;
    return *this;
}

Vec3& Vec3::operator*=(float s) {
    x *= s;
    y *= s;
    z *= s;
    return *this;
}

Vec3 operator+(Vec3 lhs, const Vec3& rhs) {
    lhs += rhs;
    return lhs;
}

Vec3 operator-(Vec3 lhs, const Vec3& rhs) {
    lhs -= rhs;
    return lhs;
}

Vec3 operator*(Vec3 v, float s) {
    v *= s;
    return v;
}

Vec3 operator*(float s, Vec3 v) {
    v *= s;
    return v;
}

Vec3 operator/(Vec3 v, float s) {
    const float inv = 1.0f / s;
    return v * inv;
}

float dot(const Vec3& a, const Vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

float length_squared(const Vec3& v) {
    return dot(v, v);
}

float length(const Vec3& v) {
    return std::sqrt(length_squared(v));
}

Material material_preset(MaterialKind kind) {
    // Tuning seeds for RC-sized structural members. These are intentionally
    // conservative placeholders until calibrated from real dimensions/tests.
    switch (kind) {
        case MaterialKind::EpoFoam:
            return {
                18000.0f, 85.0f,
                0.045f, 0.055f,
                0.38f, 0.48f,
                7.0f, 0.36f
            };
        case MaterialKind::Balsa:
            return {
                95000.0f, 55.0f,
                0.018f, 0.024f,
                0.085f, 0.11f,
                0.8f, 0.035f
            };
        case MaterialKind::Plywood:
            return {
                180000.0f, 80.0f,
                0.020f, 0.028f,
                0.12f, 0.15f,
                1.0f, 0.05f
            };
        case MaterialKind::CarbonFiber:
            return {
                420000.0f, 45.0f,
                0.012f, 0.014f,
                0.055f, 0.065f,
                0.18f, 0.012f
            };
        case MaterialKind::Aluminum:
            return {
                260000.0f, 95.0f,
                0.025f, 0.035f,
                0.22f, 0.25f,
                3.5f, 0.18f
            };
        case MaterialKind::SteelWire:
            return {
                360000.0f, 75.0f,
                0.018f, 0.024f,
                0.28f, 0.30f,
                2.4f, 0.14f
            };
        case MaterialKind::GenericComposite:
        default:
            return {
                150000.0f, 65.0f,
                0.025f, 0.030f,
                0.14f, 0.18f,
                1.2f, 0.07f
            };
    }
}

Solver::Solver(SolverConfig config) : config_(config) {
    config_.normal_substeps = std::max<std::uint32_t>(1, config_.normal_substeps);
    config_.impact_substeps = std::max<std::uint32_t>(config_.normal_substeps, config_.impact_substeps);
    config_.max_substeps = std::max<std::uint32_t>(config_.impact_substeps, config_.max_substeps);
}

void Solver::reserve(std::size_t node_capacity, std::size_t beam_capacity) {
    nodes_.reserve(node_capacity);
    forces_.reserve(node_capacity);
    beams_.reserve(beam_capacity);
    break_events_.reserve(beam_capacity);
    triggered_break_groups_.reserve(std::min<std::size_t>(beam_capacity, 64));
}

std::uint32_t Solver::add_node(Vec3 position, float mass_kg, bool pinned) {
    if (!pinned && mass_kg <= 0.0f) {
        throw std::invalid_argument("RCBeam node mass must be > 0");
    }

    Node node{};
    node.position = position;
    node.pinned = pinned;
    node.inverse_mass = pinned ? 0.0f : 1.0f / mass_kg;

    nodes_.push_back(node);
    forces_.push_back({});
    return static_cast<std::uint32_t>(nodes_.size() - 1);
}

std::uint32_t Solver::add_beam(
    std::uint32_t a,
    std::uint32_t b,
    const Material& material,
    std::uint16_t break_group
) {
    if (a >= nodes_.size() || b >= nodes_.size() || a == b) {
        throw std::invalid_argument("RCBeam beam endpoints are invalid");
    }

    const float initial = length(nodes_[b].position - nodes_[a].position);
    if (initial <= kEpsilon) {
        throw std::invalid_argument("RCBeam beam length must be > 0");
    }

    Beam beam{};
    beam.a = a;
    beam.b = b;
    beam.initial_length = initial;
    beam.rest_length = initial;
    beam.material = material;
    beam.break_group = break_group;

    beams_.push_back(beam);
    return static_cast<std::uint32_t>(beams_.size() - 1);
}

void Solver::clear() {
    nodes_.clear();
    beams_.clear();
    forces_.clear();
    triggered_break_groups_.clear();
    break_events_.clear();
    impact_timer_ = 0.0f;
}

void Solver::apply_force(std::uint32_t node, Vec3 force_n) {
    if (node < forces_.size()) {
        forces_[node] += force_n;
    }
}

void Solver::apply_impulse(std::uint32_t node, Vec3 impulse_ns) {
    if (node >= nodes_.size()) {
        return;
    }

    Node& n = nodes_[node];
    if (!n.pinned) {
        n.velocity += impulse_ns * n.inverse_mass;
        n.velocity = clamp_speed(n.velocity, config_.max_node_speed_mps);
    }
}

void Solver::apply_radial_impulse(Vec3 center, Vec3 impulse_ns, float radius_m) {
    if (radius_m <= kEpsilon) {
        return;
    }

    const float inv_radius = 1.0f / radius_m;
    for (std::uint32_t i = 0; i < nodes_.size(); ++i) {
        const Vec3 offset = nodes_[i].position - center;
        const float d = length(offset);
        if (d >= radius_m) {
            continue;
        }

        const float falloff = 1.0f - d * inv_radius;
        apply_impulse(i, impulse_ns * falloff);
    }
}

void Solver::notify_impact(float normalized_severity) {
    if (normalized_severity >= config_.impact_trigger) {
        const float weight = clampf(normalized_severity, 0.0f, 1.0f);
        impact_timer_ = std::max(
            impact_timer_,
            config_.impact_hold_seconds * (0.5f + 0.5f * weight)
        );
    }
}

void Solver::break_beam(std::uint32_t beam_index, StepStats& stats) {
    Beam& beam = beams_[beam_index];
    if (beam.broken) {
        return;
    }

    beam.broken = true;
    beam.last_force_n = 0.0f;
    ++stats.newly_broken_beams;
    break_events_.push_back(beam_index);

    if (beam.break_group != 0) {
        if (std::find(
                triggered_break_groups_.begin(),
                triggered_break_groups_.end(),
                beam.break_group
            ) == triggered_break_groups_.end()) {
            triggered_break_groups_.push_back(beam.break_group);
        }
    }
}

void Solver::trigger_break_group(std::uint16_t group, StepStats& stats) {
    if (group == 0) {
        return;
    }

    for (std::uint32_t i = 0; i < beams_.size(); ++i) {
        if (!beams_[i].broken && beams_[i].break_group == group) {
            break_beam(i, stats);
        }
    }
}

StepStats Solver::step(float dt_seconds, Vec3 external_acceleration_mps2) {
    StepStats stats{};
    if (dt_seconds <= 0.0f || nodes_.empty()) {
        return stats;
    }

    const bool impact_mode = impact_timer_ > 0.0f;
    const std::uint32_t requested = impact_mode
        ? config_.impact_substeps
        : config_.normal_substeps;
    const std::uint32_t substeps = std::max<std::uint32_t>(
        1,
        std::min(requested, config_.max_substeps)
    );
    stats.substeps = substeps;

    const float h = dt_seconds / static_cast<float>(substeps);
    const float velocity_damping = 1.0f / (1.0f + config_.global_velocity_damping * h);

    for (std::uint32_t sub = 0; sub < substeps; ++sub) {
        // Keep externally applied force for the first substep only; gravity is
        // regenerated every substep. This makes host forces frame-based and
        // avoids multiplying them by the structural substep count.
        for (std::uint32_t i = 0; i < nodes_.size(); ++i) {
            Node& node = nodes_[i];
            if (node.pinned) {
                forces_[i] = {};
                continue;
            }

            const float mass = 1.0f / node.inverse_mass;
            forces_[i] += external_acceleration_mps2 * mass;
        }

        triggered_break_groups_.clear();

        for (std::uint32_t bi = 0; bi < beams_.size(); ++bi) {
            Beam& beam = beams_[bi];
            if (beam.broken) {
                continue;
            }

            Node& a = nodes_[beam.a];
            Node& b = nodes_[beam.b];

            const Vec3 delta = b.position - a.position;
            const float current_length = length(delta);
            if (current_length <= kEpsilon) {
                continue;
            }

            const Vec3 dir = delta / current_length;
            const float extension = current_length - beam.rest_length;
            const float strain = extension / std::max(beam.rest_length, kEpsilon);
            const float relative_speed = dot(b.velocity - a.velocity, dir);

            beam.last_strain = strain;
            stats.max_abs_strain = std::max(stats.max_abs_strain, std::abs(strain));

            const float abs_strain = std::abs(strain);
            const float break_limit = strain >= 0.0f
                ? beam.material.break_tension
                : beam.material.break_compression;

            if (abs_strain >= break_limit) {
                break_beam(bi, stats);
                continue;
            }

            const float yield_limit = strain >= 0.0f
                ? beam.material.yield_tension
                : beam.material.yield_compression;

            if (abs_strain > yield_limit && beam.material.plasticity_rate > 0.0f) {
                const float overload = (abs_strain - yield_limit)
                    / std::max(break_limit - yield_limit, kEpsilon);
                const float flow = clampf(
                    beam.material.plasticity_rate * overload * h,
                    0.0f,
                    0.35f
                );

                beam.rest_length += (current_length - beam.rest_length) * flow;

                const float min_rest = beam.initial_length
                    * (1.0f - beam.material.max_plastic_strain);
                const float max_rest = beam.initial_length
                    * (1.0f + beam.material.max_plastic_strain);
                beam.rest_length = clampf(beam.rest_length, min_rest, max_rest);
            }

            const float spring_force = beam.material.stiffness_n_per_m * extension;
            const float damping_force = beam.material.damping_ns_per_m * relative_speed;
            const float force_magnitude = spring_force + damping_force;
            beam.last_force_n = force_magnitude;

            const Vec3 force = dir * force_magnitude;
            if (!a.pinned) {
                forces_[beam.a] += force;
            }
            if (!b.pinned) {
                forces_[beam.b] -= force;
            }

            ++stats.active_beams;
        }

        // A structural attachment group breaks as one event. Keep this pass
        // separate so the main beam loop stays branch-light.
        for (const std::uint16_t group : triggered_break_groups_) {
            trigger_break_group(group, stats);
        }

        for (std::uint32_t i = 0; i < nodes_.size(); ++i) {
            Node& node = nodes_[i];
            if (node.pinned) {
                node.velocity = {};
                forces_[i] = {};
                continue;
            }

            node.velocity += forces_[i] * node.inverse_mass * h;
            node.velocity *= velocity_damping;
            node.velocity = clamp_speed(node.velocity, config_.max_node_speed_mps);
            node.position += node.velocity * h;

            stats.max_node_speed_mps = std::max(
                stats.max_node_speed_mps,
                length(node.velocity)
            );

            // External forces are consumed; next substep starts from gravity
            // plus internal beam forces.
            forces_[i] = {};
        }
    }

    impact_timer_ = std::max(0.0f, impact_timer_ - dt_seconds);
    return stats;
}

std::vector<std::uint32_t> Solver::consume_break_events() {
    std::vector<std::uint32_t> out;
    out.swap(break_events_);
    // Keep the hot buffer capacity for future events.
    break_events_.reserve(beams_.capacity());
    return out;
}

} // namespace rcbeam
