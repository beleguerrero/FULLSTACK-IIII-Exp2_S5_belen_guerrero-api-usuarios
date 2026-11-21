package cl.duoc.mi_foro_usuarios.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cl.duoc.mi_foro_usuarios.dto.LoginRequestDTO;
import cl.duoc.mi_foro_usuarios.dto.LoginResponseDTO;
import cl.duoc.mi_foro_usuarios.service.UsuarioService;

@RestController 
@RequestMapping
public class AuthController {

    private final UsuarioService service;

    public AuthController(UsuarioService service) {
        this.service = service;
    }

    @PostMapping("/api/auth/login")
    public ResponseEntity<LoginResponseDTO> login(@RequestBody LoginRequestDTO body) {
        return ResponseEntity.ok(service.login(body));
    }

}
