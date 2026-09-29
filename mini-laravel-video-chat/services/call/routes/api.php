<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\RoomController;

Route::post('/rooms', [RoomController::class, 'store']);

Route::get('/rooms/{roomId}', [RoomController::class, 'show']);

Route::delete('/rooms/{roomId}', [RoomController::class, 'destroy']);
