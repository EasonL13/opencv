/*M///////////////////////////////////////////////////////////////////////////////////////
//
//  IMPORTANT: READ BEFORE DOWNLOADING, COPYING, INSTALLING OR USING.
//
//  By downloading, copying, installing or using the software you agree to this license.
//  If you do not agree to this license, do not download, install,
//  copy or use the software.
//
//
//                           License Agreement
//                For Open Source Computer Vision Library
//
// Copyright (C) 2010-2012, Institute Of Software Chinese Academy Of Science, all rights reserved.
// Copyright (C) 2010-2012, Advanced Micro Devices, Inc., all rights reserved.
// Third party copyrights are property of their respective owners.
//
// @Authors
//    Jia Haipeng, jiahaipeng95@gmail.com
//    Peng Xiao, pengxiao@multicorewareinc.com
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//   * Redistribution's of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//   * Redistribution's in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//   * The name of the copyright holders may not be used to endorse or promote products
//     derived from this software without specific prior written permission.
//
// This software is provided by the copyright holders and contributors as is and
// any express or implied warranties, including, but not limited to, the implied
// warranties of merchantability and fitness for a particular purpose are disclaimed.
// In no event shall the Intel Corporation or contributors be liable for any direct,
// indirect, incidental, special, exemplary, or consequential damages
// (including, but not limited to, procurement of substitute goods or services;
// loss of use, data, or profits; or business interruption) however caused
// and on any theory of liability, whether in contract, strict liability,
// or tort (including negligence or otherwise) arising in any way out of
// the use of this software, even if advised of the possibility of such damage.
//
//M*/

/**************************************PUBLICFUNC*************************************/

#ifndef hscale
#define hscale 0
#endif

#ifndef hrange
#define hrange 0
#endif

#ifdef DEPTH_0
#define DATA_TYPE uchar
#define COEFF_TYPE int
#define MAX_NUM  255
#define HALF_MAX 128
#define SAT_CAST(num) convert_uchar_sat_rte(num)
#endif

#ifdef DEPTH_2
#define DATA_TYPE ushort
#define COEFF_TYPE int
#define MAX_NUM  65535
#define HALF_MAX 32768
#define SAT_CAST(num) convert_ushort_sat_rte(num)
#endif

#ifdef DEPTH_5
#define DATA_TYPE float
#define COEFF_TYPE float
#define MAX_NUM  1.0f
#define HALF_MAX 0.5f
#define SAT_CAST(num) (num)
#endif

#define CV_DESCALE(x, n) (((x) + (1 << ((n)-1))) >> (n))

enum
{
    yuv_shift  = 14,
    xyz_shift  = 12,
    hsv_shift = 12,
    R2Y        = 4899,
    G2Y        = 9617,
    B2Y        = 1868,
    BLOCK_SIZE = 256
};

__constant int sector_data[][3] = { {1, 3, 0}, { 1, 0, 2 }, { 3, 0, 1 }, { 0, 2, 1 }, { 0, 1, 3 }, { 2, 1, 0 } };

///////////////////////////////////// RGB <-> HLS //////////////////////////////////////

#ifdef DEPTH_0

__kernel void RGB2HLS(int cols, int rows, int src_step, int dst_step, int bidx,
                      __global const uchar * src, __global uchar * dst,
                      int src_offset, int dst_offset)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (y < rows && x < cols)
    {
        x <<= 2;
        int src_idx = mad24(y, src_step, src_offset + x);
        int dst_idx = mad24(y, dst_step, dst_offset + x);

        float b = src[src_idx + bidx]*(1/255.f), g = src[src_idx + 1]*(1/255.f), r = src[src_idx + (bidx^2)]*(1/255.f);
        float h = 0.f, s = 0.f, l;
        float vmin, vmax, diff;

        vmax = vmin = r;
        if (vmax < g) vmax = g;
        if (vmax < b) vmax = b;
        if (vmin > g) vmin = g;
        if (vmin > b) vmin = b;

        diff = vmax - vmin;
        l = (vmax + vmin)*0.5f;

        if (diff > FLT_EPSILON)
        {
            s = l < 0.5f ? diff/(vmax + vmin) : diff/(2 - vmax - vmin);
            diff = 60.f/diff;

            if( vmax == r )
                h = (g - b)*diff;
            else if( vmax == g )
                h = (b - r)*diff + 120.f;
            else
                h = (r - g)*diff + 240.f;

            if( h < 0.f ) h += 360.f;
        }

        dst[dst_idx] = convert_uchar_sat_rte(h*hscale);
        dst[dst_idx + 1] = convert_uchar_sat_rte(l*255.f);
        dst[dst_idx + 2] = convert_uchar_sat_rte(s*255.f);
    }
}

__kernel void HLS2RGB(int cols, int rows, int src_step, int dst_step, int bidx,
                      __global const uchar * src, __global uchar * dst,
                      int src_offset, int dst_offset)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (y < rows && x < cols)
    {
        x <<= 2;
        int src_idx = mad24(y, src_step, src_offset + x);
        int dst_idx = mad24(y, dst_step, dst_offset + x);

        float h = src[src_idx], l = src[src_idx + 1]*(1.f/255.f), s = src[src_idx + 2]*(1.f/255.f);
        float b, g, r;

        if (s != 0)
        {
            float tab[4];

            float p2 = l <= 0.5f ? l*(1 + s) : l + s - l*s;
            float p1 = 2*l - p2;

            h *= hscale;
            if( h < 0 )
                do h += 6; while( h < 0 );
            else if( h >= 6 )
                do h -= 6; while( h >= 6 );

            int sector = convert_int_sat_rtn(h);
            h -= sector;

            tab[0] = p2;
            tab[1] = p1;
            tab[2] = p1 + (p2 - p1)*(1-h);
            tab[3] = p1 + (p2 - p1)*h;

            b = tab[sector_data[sector][0]];
            g = tab[sector_data[sector][1]];
            r = tab[sector_data[sector][2]];
        }
        else
            b = g = r = l;

        dst[dst_idx + bidx] = convert_uchar_sat_rte(b*255.f);
        dst[dst_idx + 1] = convert_uchar_sat_rte(g*255.f);
        dst[dst_idx + (bidx^2)] = convert_uchar_sat_rte(r*255.f);
#if dcn == 4
        dst[dst_idx + 3] = MAX_NUM;
#endif
    }
}

#elif defined DEPTH_5

__kernel void RGB2HLS(int cols, int rows, int src_step, int dst_step, int bidx,
                      __global const float * src, __global float * dst,
                      int src_offset, int dst_offset)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (y < rows && x < cols)
    {
        x <<= 2;
        int src_idx = mad24(y, src_step, src_offset + x);
        int dst_idx = mad24(y, dst_step, dst_offset + x);

        float b = src[src_idx + bidx], g = src[src_idx + 1], r = src[src_idx + (bidx^2)];
        float h = 0.f, s = 0.f, l;
        float vmin, vmax, diff;

        vmax = vmin = r;
        if (vmax < g) vmax = g;
        if (vmax < b) vmax = b;
        if (vmin > g) vmin = g;
        if (vmin > b) vmin = b;

        diff = vmax - vmin;
        l = (vmax + vmin)*0.5f;

        if (diff > FLT_EPSILON)
        {
            s = l < 0.5f ? diff/(vmax + vmin) : diff/(2 - vmax - vmin);
            diff = 60.f/diff;

            if( vmax == r )
                h = (g - b)*diff;
            else if( vmax == g )
                h = (b - r)*diff + 120.f;
            else
                h = (r - g)*diff + 240.f;

            if( h < 0.f ) h += 360.f;
        }

        dst[dst_idx] = h*hscale;
        dst[dst_idx + 1] = l;
        dst[dst_idx + 2] = s;
    }
}

__kernel void HLS2RGB(int cols, int rows, int src_step, int dst_step, int bidx,
                      __global const float * src, __global float * dst,
                      int src_offset, int dst_offset)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (y < rows && x < cols)
    {
        x <<= 2;
        int src_idx = mad24(y, src_step, src_offset + x);
        int dst_idx = mad24(y, dst_step, dst_offset + x);

        float h = src[src_idx], l = src[src_idx + 1], s = src[src_idx + 2];
        float b, g, r;

        if (s != 0)
        {
            float tab[4];
            int sector;

            float p2 = l <= 0.5f ? l*(1 + s) : l + s - l*s;
            float p1 = 2*l - p2;

            h *= hscale;
            if( h < 0 )
                do h += 6; while( h < 0 );
            else if( h >= 6 )
                do h -= 6; while( h >= 6 );

            sector = convert_int_sat_rtn(h);
            h -= sector;

            tab[0] = p2;
            tab[1] = p1;
            tab[2] = p1 + (p2 - p1)*(1-h);
            tab[3] = p1 + (p2 - p1)*h;

            b = tab[sector_data[sector][0]];
            g = tab[sector_data[sector][1]];
            r = tab[sector_data[sector][2]];
        }
        else
            b = g = r = l;

        dst[dst_idx + bidx] = b;
        dst[dst_idx + 1] = g;
        dst[dst_idx + (bidx^2)] = r;
#if dcn == 4
        dst[dst_idx + 3] = MAX_NUM;
#endif
    }
}

#endif

/////////////////////////// RGBA <-> mRGBA (alpha premultiplied) //////////////

#ifdef DEPTH_0

__kernel void RGBA2mRGBA(int cols, int rows, int src_step, int dst_step,
                        int bidx, __global const uchar * src, __global uchar * dst,
                        int src_offset, int dst_offset)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (y < rows && x < cols)
    {
        x <<= 2;
        int src_idx = mad24(y, src_step, src_offset + x);
        int dst_idx = mad24(y, dst_step, dst_offset + x);

        uchar v0 = src[src_idx], v1 = src[src_idx + 1];
        uchar v2 = src[src_idx + 2], v3 = src[src_idx + 3];

        dst[dst_idx] = (v0 * v3 + HALF_MAX) / MAX_NUM;
        dst[dst_idx + 1] = (v1 * v3 + HALF_MAX) / MAX_NUM;
        dst[dst_idx + 2] = (v2 * v3 + HALF_MAX) / MAX_NUM;
        dst[dst_idx + 3] = v3;
    }
}

__kernel void mRGBA2RGBA(int cols, int rows, int src_step, int dst_step, int bidx,
                        __global const uchar * src, __global uchar * dst,
                        int src_offset, int dst_offset)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (y < rows && x < cols)
    {
        x <<= 2;
        int src_idx = mad24(y, src_step, src_offset + x);
        int dst_idx = mad24(y, dst_step, dst_offset + x);

        uchar v0 = src[src_idx], v1 = src[src_idx + 1];
        uchar v2 = src[src_idx + 2], v3 = src[src_idx + 3];
        uchar v3_half = v3 / 2;

        dst[dst_idx] = v3 == 0 ? 0 : (v0 * MAX_NUM + v3_half) / v3;
        dst[dst_idx + 1] = v3 == 0 ? 0 : (v1 * MAX_NUM + v3_half) / v3;
        dst[dst_idx + 2] = v3 == 0 ? 0 : (v2 * MAX_NUM + v3_half) / v3;
        dst[dst_idx + 3] = v3;
    }
}

#endif
