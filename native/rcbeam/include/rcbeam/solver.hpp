#pragma once

#include <cstdint>
#include <vector>

namespace rcbeam {

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;

    Vec3& operator+=(const Vec3& rhs);
    Vec3& operator-=(const Vec3& rhs);
    Vec3& operator*=(float s);
};

Vec3 operator+(Vec3 lhs, const Vec3& rhs);
Vec3 operator-(Vec3 lhs, const Vec3& rhs);
Vec3 operator*(Vec3 v, float s);
Vec3 operator*(float s, Vec3 v);
Vec3 operator/(Vec3 v, float s);
float dot(const Vec3& a, const Vec3& b);
float length_squared(const Vec3& v);
float length(const Vec3& v);

enum class MaterialKind : std::uint8_t {
    EpoFoam,
    Balsa,
    Plywood,
    CarbonFiber,
    Aluminum,
    SteelWire,
    GenericComposite
};

struct Material {
    float stiffness_n_per_m = 30000.0f;
    float damping_ns_per_m = 45.0f;

    // Positive dimensionless strain magnitudes.
    float yield_tension = 0.06f;
    float yield_compression = 0.08f;
    float break_tension = 0.24f;
    float break_compression = 0.30f;

    // Fractional rate toward the overloaded length, per second.
    float plasticity_rate = 4.0f;

    // Maximum permanent rest-length change relative to initial length.
    float max_plastic_strain = 0.25f;
};

Material material_preset(MaterialKind kind);

struct Node {
    Vec3 position{};
    Vec3 velocity{};
    float inverse_mass = 1.0f;
    bool pinned = false;
};

struct Beam {
    std::uint32_t a = 0;
    std::uint32_t b = 0;

    float initial_length = 0.0f;
    float rest_length = 0.0f;

    Material material{};
    std::uint16_t break_group = 0;

    float last_force_n = 0.0f;
    float last_strain = 0.0f;
    bool broken = false;
};

struct SolverConfig {
    // Designed for a 120 Hz host physics loop.
    std::uint32_t normal_substeps = 4; // 480 Hz structural solve
    std::uint32_t impact_substeps = 8; // 960 Hz bounded impact solve
    std::uint32_t max_substeps = 8;

    float impact_hold_seconds = 0.12f;
    float impact_trigger = 0.25f; // normalized [0,1] hint from host contact logic

    // Numerical safety; should be far above normal RC speeds.
    float max_node_speed_mps = 250.0f;
    float global_velocity_damping = 0.015f;
};

struct StepStats {
    std::uint32_t substeps = 0;
    std::uint32_t active_beams = 0;
    std::uint32_t newly_broken_beams = 0;

    float max_abs_strain = 0.0f;
    float max_node_speed_mps = 0.0f;
};

class Solver {
public:
    static constexpr std::uint32_t INVALID_INDEX = 0xFFFFFFFFu;

    explicit Solver(SolverConfig config = {});

    void reserve(std::size_t node_capacity, std::size_t beam_capacity);

    std::uint32_t add_node(Vec3 position, float mass_kg, bool pinned = false);
    std::uint32_t add_beam(
        std::uint32_t a,
        std::uint32_t b,
        const Material& material,
        std::uint16_t break_group = 0
    );

    void clear();

    // External loads accumulate until the next step starts.
    void apply_force(std::uint32_t node, Vec3 force_n);
    void apply_impulse(std::uint32_t node, Vec3 impulse_ns);
    void apply_radial_impulse(Vec3 center, Vec3 impulse_ns, float radius_m);

    // 0..1 hint. High values enable the bounded high-rate impact window.
    void notify_impact(float normalized_severity);

    StepStats step(float dt_seconds, Vec3 external_acceleration_mps2 = {0.0f, -9.81f, 0.0f});

    const std::vector<Node>& nodes() const { return nodes_; }
    const std::vector<Beam>& beams() const { return beams_; }

    std::vector<std::uint32_t> consume_break_events();

private:
    SolverConfig config_{};

    std::vector<Node> nodes_{};
    std::vector<Beam> beams_{};
    std::vector<Vec3> forces_{};

    // Reused buffers: no allocations in the steady-state step path after reserve.
    std::vector<std::uint16_t> triggered_break_groups_{};
    std::vector<std::uint32_t> break_events_{};

    float impact_timer_ = 0.0f;

    void trigger_break_group(std::uint16_t group, StepStats& stats);
    void break_beam(std::uint32_t beam_index, StepStats& stats);
};

} // namespace rcbeam
