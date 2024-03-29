module sdl;

/*
    SDL - Simple DirectMedia Layer
    Copyright (C) 1997-2012 Sam Lantinga
    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.
    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.
    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
    Sam Lantinga
    slouken@libsdl.org
*/

extern (C):
@nogc: nothrow:

public import sdl.audio;

/** @name SDL_INIT Flags
 *  These are the flags which may be passed to SDL_Init() -- you should
 *  specify the subsystems which you will be using in your application.
 */
/*@{*/
enum SDL_INIT_TIMER       = 0x00000001;
enum SDL_INIT_AUDIO       = 0x00000010;
enum SDL_INIT_VIDEO       = 0x00000020;
enum SDL_INIT_CDROM       = 0x00000100;
enum SDL_INIT_JOYSTICK    = 0x00000200;
enum SDL_INIT_NOPARACHUTE = 0x00100000;  /**< Don't catch fatal signals */
enum SDL_INIT_EVENTTHREAD = 0x01000000;  /**< Not supported on all OS's */
enum SDL_INIT_EVERYTHING  = 0x0000FFFF;
/*@}*/

/** This function loads the SDL dynamically linked library and initializes
 *  the subsystems specified by 'flags' (and those satisfying dependencies)
 *  Unless the SDL_INIT_NOPARACHUTE flag is set, it will install cleanup
 *  signal handlers for some commonly ignored fatal signals (like SIGSEGV)
 */
int SDL_Init(uint flags);

/** This function initializes specific SDL subsystems */
int SDL_InitSubsystem(uint flags);

/** This function cleans up specific SDL subsystems */
void SDL_QuitSubSystem(uint flags);

/** This function returns mask of the specified subsystems which have
 *  been initialized.
 *  If 'flags' is 0, it returns a mask of all initialized subsystems.
 */
uint SDL_WasInit(uint flags);

/** This function cleans up all initialized subsystems and unloads the
 *  dynamically linked library.  You should call it upon all exit conditions.
 */
void SDL_Quit();
