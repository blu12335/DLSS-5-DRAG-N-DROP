/*=============================================================================
                                                           
 d8b 888b     d888 888b     d888 8888888888 8888888b.   .d8888b.  8888888888 
 Y8P 8888b   d8888 8888b   d8888 888        888   Y88b d88P  Y88b 888        
     88888b.d88888 88888b.d88888 888        888    888 Y88b.      888        
 888 888Y88888P888 888Y88888P888 8888888    888   d88P  "Y888b.   8888888    
 888 888 Y888P 888 888 Y888P 888 888        8888888P"      "Y88b. 888        
 888 888  Y8P  888 888  Y8P  888 888        888 T88b         "888 888        
 888 888   "   888 888   "   888 888        888  T88b  Y88b  d88P 888        
 888 888       888 888       888 8888888888 888   T88b  "Y8888P"  8888888888                                                                 
                                                                            
    Copyright (c) Pascal Gilcher. All rights reserved.
    
    * Unauthorized copying of this file, via any medium is strictly prohibited
 	* Proprietary and confidential

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.

===============================================================================

    Depth Enhanced Local Contrast Sharpen v1.0

    Author:         Pascal Gilcher

    More info:      https://martysmods.com
                    https://patreon.com/mcflypg
                    https://github.com/martymcmodding  	

=============================================================================*/

/*=============================================================================
	Preprocessor settings
=============================================================================*/

/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform float SHARP_AMT <
	ui_type = "drag";
    ui_label = "Sharpen Intensity";
	ui_min = 0.0; 
    ui_max = 1.0;
> = 1.0;

uniform int QUALITY <
	ui_type = "combo";
    ui_label = "Sharpen Preset";
    ui_items = "Simple\0Advanced\0";
	ui_min = 0; 
    ui_max = 1;
> = 1;

/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

texture ColorInputTex : COLOR;
texture DepthInputTex : DEPTH;
sampler ColorInput 	{ Texture = ColorInputTex; }; //Local Laplacian looks better when filtered in gamma space
sampler DepthInput  { Texture = DepthInputTex; };

#include ".\MartysMods\mmx_global.fxh"
#include ".\MartysMods\mmx_depth.fxh"
#include ".\MartysMods\mmx_math.fxh"

struct VSOUT
{
    float4 vpos : SV_Position;
    float2 uv   : TEXCOORD0;
};

/*=============================================================================
	Functions
=============================================================================*/

float3 remap_function(float3 x, float3 gaussian, float alpha)
{       
    float3 s = 6.0; //scale of laplacian bump
    float3 bsx = 0.7 * s * (x - gaussian);
    bsx = clamp(bsx, -HALF_PI, HALF_PI);
    float3 curve = alpha * 0.7 * (sin(bsx * 3.141) + tanh(bsx * 4)) / s;
    return x + curve;
}

/*=============================================================================
	Shader Entry Points
=============================================================================*/

VSOUT MainVS(in uint id : SV_VertexID)
{
    VSOUT o;
    FullscreenTriangleVS(id, o.vpos, o.uv); //use original fullscreen triangle VS
    return o;
}

//This is essentially the local laplacian algorithm, except we stop immediately after one level
void MainPS(in VSOUT i, out float3 o : SV_Target0)
{
    int2 p = int2(i.vpos.xy);
    float3 c = tex2Dfetch(ColorInput, p).rgb;
    float d = Depth::get_linear_depth(i.uv);

    const int2 offsets[8] = 
    {
        int2(1, 0),
        int2(-1, 0),
        int2(0, 1),
        int2(0, -1),
        //corners
        int2(1, 1),
        int2(-1, 1),
        int2(1, -1),
        int2(-1, -1)
    };

    float4 G1 = float4(c, 1) * 4;//center weights 4x
    float4 L0 = float4(c, 1) * 4; 
    float4 weights = 1;

    //sides
    {
        float3 tap0, tap1, tap2, tap3;
        tap0 = tex2Dfetch(ColorInput, p + offsets[0]).rgb;
        tap1 = tex2Dfetch(ColorInput, p + offsets[1]).rgb;
        tap2 = tex2Dfetch(ColorInput, p + offsets[2]).rgb;
        tap3 = tex2Dfetch(ColorInput, p + offsets[3]).rgb;

        [branch]
        if(QUALITY == 1)
        {
            float4 depths;
            depths.x = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[0]);
            depths.y = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[1]);
            depths.z = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[2]);
            depths.w = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[3]);
            weights = saturate(1 - 1000 * abs(depths - d));
        }

        weights *= 2;  //+ weights 2x       

        G1 += float4(tap0, 1) * weights.x;
        G1 += float4(tap1, 1) * weights.y;
        G1 += float4(tap2, 1) * weights.z;
        G1 += float4(tap3, 1) * weights.w;
        L0 += float4(remap_function(tap0, c, SHARP_AMT), 1) * weights.x;
        L0 += float4(remap_function(tap1, c, SHARP_AMT), 1) * weights.y;
        L0 += float4(remap_function(tap2, c, SHARP_AMT), 1) * weights.z;
        L0 += float4(remap_function(tap3, c, SHARP_AMT), 1) * weights.w;
    }
    //corners 
    [branch]
    if(QUALITY == 1)        
    {
        float3 tap0, tap1, tap2, tap3;
        tap0 = tex2Dfetch(ColorInput, p + offsets[4]).rgb;
        tap1 = tex2Dfetch(ColorInput, p + offsets[5]).rgb;
        tap2 = tex2Dfetch(ColorInput, p + offsets[6]).rgb;
        tap3 = tex2Dfetch(ColorInput, p + offsets[7]).rgb;
       
        float4 depths;
        depths.x = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[4]);
        depths.y = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[5]);
        depths.z = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[6]);
        depths.w = Depth::get_linear_depth(i.uv + BUFFER_PIXEL_SIZE * offsets[7]);
        weights = saturate(1 - 1000 * abs(depths - d)) * 1; //X weights 1x       
            
        G1 += float4(tap0, 1) * weights.x;
        G1 += float4(tap1, 1) * weights.y;
        G1 += float4(tap2, 1) * weights.z;
        G1 += float4(tap3, 1) * weights.w;
        L0 += float4(remap_function(tap0, c, SHARP_AMT), 1) * weights.x;
        L0 += float4(remap_function(tap1, c, SHARP_AMT), 1) * weights.y;
        L0 += float4(remap_function(tap2, c, SHARP_AMT), 1) * weights.z;
        L0 += float4(remap_function(tap3, c, SHARP_AMT), 1) * weights.w;
    }

    G1.rgb /= G1.w;
    L0.rgb /= L0.w;

    //now the laplacian logic
    //for local laplacian, each texel in the final laplacian pyramid is the texel out of a dedicated laplacian pyramid
    //built from a gaussian pyramid from the fullres image rebalanced with the corresponding texel from the original gaussian pyramid

    //if this is confusing, that's because it is. L0 is now the final laplacian layer taken from a gaussian pyramid 
    //from the source image that has been rebalanced around the corresponding gaussian texel - which for fullres is our fullres texel
 
    L0.rgb = c.rgb - L0.rgb; 
    o = L0.rgb + G1.rgb; //add the residual 
}


/*=============================================================================
	Techniques
=============================================================================*/

technique MartyMods_Sharpen
<
    ui_label = "iMMERSE: Sharpen";
    ui_tooltip =        
        "                             MartysMods - Sharpen                             \n"
        "                   MartysMods Epic ReShade Effects (iMMERSE)                  \n"
        "______________________________________________________________________________\n"
        "\n"

        "The Depth Enhanced Local Contrast Sharpen is a high quality sharpen effect for\n"
        "ReShade, which can enhance texture detail and reduce TAA blur.                \n"
        "\n"
        "\n"
        "Visit https://martysmods.com for more information.                            \n"
        "\n"       
        "______________________________________________________________________________";
>
{    
    pass
	{
		VertexShader = MainVS;
		PixelShader  = MainPS; 
	}     
}