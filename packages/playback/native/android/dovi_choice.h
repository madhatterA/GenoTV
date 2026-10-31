#ifndef VP_DOVI_CHOICE_H
#define VP_DOVI_CHOICE_H

/* Android CodecProfileLevel uses a bit per Dolby Vision profile/level. */
typedef struct VPDoviChoice {
    const char *mime;
    int profile, level;
    int incompatible_base;
} VPDoviChoice;

static inline VPDoviChoice vp_dovi_choice(int profile, int level, int has_decoder)
{
    const int hevc_dovi = profile >= 2 && profile <= 8;
    const int valid = hevc_dovi && level >= 1 && level <= 12;
    if (valid && has_decoder)
        return (VPDoviChoice){"video/dolby-vision", 1 << profile, 1 << (level - 1), 0};
    return (VPDoviChoice){"video/hevc", 0, 0, profile == 5};
}
static inline int vp_dovi_supports(int profile, int level, int supported_profile,
                                   int supported_level)
{
    return supported_profile == profile && supported_level >= level;
}
#endif
